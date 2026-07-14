(() => {
  const canvas = document.getElementById('globe');
  const selectionTitle = document.getElementById('selectionTitle');
  const selectionDetails = document.getElementById('selectionDetails');
  const toggleImagery = document.getElementById('toggleImagery');
  const toggleFeatures = document.getElementById('toggleFeatures');
  const toggleRoutes = document.getElementById('toggleRoutes');

  const gl = canvas.getContext('webgl', { antialias: true, alpha: false, preserveDrawingBuffer: false });
  if (!gl) {
    selectionTitle.textContent = 'WebGL unavailable';
    selectionDetails.textContent = 'This browser cannot create a WebGL context.';
    return;
  }

  const state = {
    yaw: -0.72,
    pitch: 0.28,
    distance: 3.75,
    dragging: false,
    lastX: 0,
    lastY: 0,
    selectedIndex: -1,
    mouseX: 0,
    mouseY: 0,
  };

  const features = [
    { id: 1, name: 'North Harbor Node', lat: 37.7749, lon: -122.4194, category: 'Facility', color: [0.95, 0.76, 0.35, 1] },
    { id: 2, name: 'Ridge Relay', lat: 34.0522, lon: -118.2437, category: 'Sensor', color: [0.33, 0.85, 0.92, 1] },
    { id: 3, name: 'Coastal Ops Cell', lat: 47.6062, lon: -122.3321, category: 'City', color: [0.58, 0.95, 0.46, 1] },
    { id: 4, name: 'Forward Cache', lat: 35.6895, lon: 139.6917, category: 'Route Point', color: [0.98, 0.42, 0.28, 1] },
    { id: 5, name: 'Imagery Index', lat: 51.5074, lon: -0.1278, category: 'Note', color: [0.85, 0.78, 0.98, 1] },
    { id: 6, name: 'Southern Sensor', lat: -33.8688, lon: 151.2093, category: 'Sensor', color: [0.72, 0.91, 1, 1] },
  ];

  const routes = [
    { name: 'Harbor to Cache', start: { lat: 37.7749, lon: -122.4194 }, end: { lat: 35.6895, lon: 139.6917 } },
    { name: 'Ops Link', start: { lat: 47.6062, lon: -122.3321 }, end: { lat: 51.5074, lon: -0.1278 } },
  ];

  const sphere = buildSphere(64, 96);
  const sphereBuffer = createArrayBuffer(gl, sphere.positions);
  const sphereNormalBuffer = createArrayBuffer(gl, sphere.normals);
  const sphereUvBuffer = createArrayBuffer(gl, sphere.uvs);
  const sphereIndexBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, sphereIndexBuffer);
  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, sphere.indices, gl.STATIC_DRAW);

  const routeGeometries = routes.map((route) => {
    const geometry = buildRoute(route, 1.01, 48);
    return {
      buffer: createArrayBuffer(gl, geometry.positions),
      vertexCount: geometry.positions.length / 3,
    };
  });

  const featureGeometry = buildFeaturePoints(features, 1.025);
  const featureBuffer = createArrayBuffer(gl, featureGeometry.positions);
  const featureColorBuffer = createArrayBuffer(gl, featureGeometry.colors);
  const featureSizeBuffer = createArrayBuffer(gl, featureGeometry.sizes);

  const selectedPoint = {
    position: gl.createBuffer(),
    color: gl.createBuffer(),
    size: gl.createBuffer(),
    visible: false,
  };

  const imageTexture = createImageryTexture(gl);

  const programs = {
    sphere: createProgram(gl, `
      attribute vec3 aPosition;
      attribute vec3 aNormal;
      attribute vec2 aUv;

      uniform mat4 uViewProj;
      uniform vec3 uSunDir;

      varying vec2 vUv;
      varying float vLight;

      void main() {
        vec3 n = normalize(aNormal);
        vUv = aUv;
        vLight = 0.35 + 0.65 * max(dot(n, normalize(uSunDir)), 0.0);
        gl_Position = uViewProj * vec4(aPosition, 1.0);
      }
    `, `
      precision mediump float;

      uniform sampler2D uTexture;
      uniform float uUseTexture;

      varying vec2 vUv;
      varying float vLight;

      void main() {
        vec3 baseColor = vec3(0.12, 0.22, 0.42);
        vec4 texColor = texture2D(uTexture, vUv);
        vec3 color = mix(baseColor, texColor.rgb, uUseTexture);
        color *= vLight;
        gl_FragColor = vec4(color, 1.0);
      }
    `),

    lines: createProgram(gl, `
      attribute vec3 aPosition;
      uniform mat4 uViewProj;

      void main() {
        gl_Position = uViewProj * vec4(aPosition, 1.0);
      }
    `, `
      precision mediump float;
      uniform vec4 uColor;

      void main() {
        gl_FragColor = uColor;
      }
    `),

    points: createProgram(gl, `
      attribute vec3 aPosition;
      attribute vec4 aColor;
      attribute float aSize;

      uniform mat4 uViewProj;

      varying vec4 vColor;

      void main() {
        vColor = aColor;
        gl_Position = uViewProj * vec4(aPosition, 1.0);
        gl_PointSize = aSize;
      }
    `, `
      precision mediump float;
      varying vec4 vColor;

      void main() {
        vec2 p = gl_PointCoord * 2.0 - 1.0;
        float r = dot(p, p);
        if (r > 1.0) discard;
        float alpha = smoothstep(1.0, 0.1, r);
        gl_FragColor = vec4(vColor.rgb, vColor.a * alpha);
      }
    `),
  };

  const locations = {
    sphere: getLocations(gl, programs.sphere, ['aPosition', 'aNormal', 'aUv'], ['uViewProj', 'uSunDir', 'uTexture', 'uUseTexture']),
    lines: getLocations(gl, programs.lines, ['aPosition'], ['uViewProj', 'uColor']),
    points: getLocations(gl, programs.points, ['aPosition', 'aColor', 'aSize'], ['uViewProj']),
  };

  gl.enable(gl.DEPTH_TEST);
  gl.enable(gl.CULL_FACE);
  gl.cullFace(gl.BACK);

  let projectedFeatures = [];

  syncSelectedPoint();

  function resize() {
    const dpr = Math.max(1, Math.min(window.devicePixelRatio || 1, 2));
    const width = Math.floor(canvas.clientWidth * dpr);
    const height = Math.floor(canvas.clientHeight * dpr);
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
    gl.viewport(0, 0, canvas.width, canvas.height);
  }

  function render() {
    resize();

    const aspect = canvas.width / canvas.height;
    const projection = mat4Perspective(0.9, aspect, 0.1, 100.0);
    const eye = orbitEye(state.yaw, state.pitch, state.distance);
    const view = mat4LookAt(eye, [0, 0, 0], [0, 1, 0]);
    const viewProj = mat4Multiply(projection, view);

    projectedFeatures = features.map((feature, index) => {
      const world = latLonToCartesian(feature.lat, feature.lon, 1.025);
      const screen = projectPoint(viewProj, world, canvas.width, canvas.height);
      return {
        index,
        world,
        screen,
        feature,
      };
    });

    gl.clearColor(0.03, 0.06, 0.11, 1.0);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

    drawSphere(viewProj);
    if (toggleRoutes.checked) {
      drawRoutes(viewProj);
    }
    if (toggleFeatures.checked) {
      drawFeaturePoints(viewProj);
    }
    if (state.selectedIndex >= 0 && toggleFeatures.checked) {
      drawSelectedPoint(viewProj);
    }

    requestAnimationFrame(render);
  }

  function drawSphere(viewProj) {
    gl.useProgram(programs.sphere);

    bindAttribute(gl, locations.sphere.aPosition, sphereBuffer, 3);
    bindAttribute(gl, locations.sphere.aNormal, sphereNormalBuffer, 3);
    bindAttribute(gl, locations.sphere.aUv, sphereUvBuffer, 2);

    gl.uniformMatrix4fv(locations.sphere.uViewProj, false, viewProj);
    gl.uniform3f(locations.sphere.uSunDir, -0.6, 0.7, 0.3);
    gl.uniform1i(locations.sphere.uTexture, 0);
    gl.uniform1f(locations.sphere.uUseTexture, toggleImagery.checked ? 1.0 : 0.0);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, imageTexture);

    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, sphereIndexBuffer);
    gl.drawElements(gl.TRIANGLES, sphere.indices.length, gl.UNSIGNED_SHORT, 0);
  }

  function drawRoutes(viewProj) {
    gl.useProgram(programs.lines);
    gl.uniformMatrix4fv(locations.lines.uViewProj, false, viewProj);
    gl.uniform4f(locations.lines.uColor, 0.36, 0.85, 0.92, 0.85);

    for (const route of routeGeometries) {
      bindAttribute(gl, locations.lines.aPosition, route.buffer, 3);
      gl.drawArrays(gl.LINE_STRIP, 0, route.vertexCount);
    }
  }

  function drawFeaturePoints(viewProj) {
    gl.useProgram(programs.points);
    bindAttribute(gl, locations.points.aPosition, featureBuffer, 3);
    bindAttribute(gl, locations.points.aColor, featureColorBuffer, 4);
    bindAttribute(gl, locations.points.aSize, featureSizeBuffer, 1);
    gl.uniformMatrix4fv(locations.points.uViewProj, false, viewProj);
    gl.drawArrays(gl.POINTS, 0, features.length);
  }

  function drawSelectedPoint(viewProj) {
    if (!selectedPoint.visible) {
      return;
    }

    gl.useProgram(programs.points);
    bindAttribute(gl, locations.points.aPosition, selectedPoint.position, 3);
    bindAttribute(gl, locations.points.aColor, selectedPoint.color, 4);
    bindAttribute(gl, locations.points.aSize, selectedPoint.size, 1);
    gl.uniformMatrix4fv(locations.points.uViewProj, false, viewProj);
    gl.drawArrays(gl.POINTS, 0, 1);
  }

  function updateSelectionPanel() {
    if (state.selectedIndex < 0) {
      syncSelectedPoint();
      selectionTitle.textContent = 'None selected';
      selectionDetails.textContent = 'Click a point on the globe.';
      return;
    }

    const feature = features[state.selectedIndex];
    syncSelectedPoint();
    selectionTitle.textContent = feature.name;
    selectionDetails.textContent = `${feature.category} | ${feature.lat.toFixed(3)}, ${feature.lon.toFixed(3)} | ${feature.lat > 0 ? 'N' : 'S'} ${Math.abs(feature.lat).toFixed(3)} / ${feature.lon > 0 ? 'E' : 'W'} ${Math.abs(feature.lon).toFixed(3)}`;
  }

  function syncSelectedPoint() {
    if (state.selectedIndex < 0) {
      selectedPoint.visible = false;
      return;
    }

    const feature = features[state.selectedIndex];
    const world = latLonToCartesian(feature.lat, feature.lon, 1.04);
    selectedPoint.visible = true;

    gl.bindBuffer(gl.ARRAY_BUFFER, selectedPoint.position);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(world), gl.DYNAMIC_DRAW);

    gl.bindBuffer(gl.ARRAY_BUFFER, selectedPoint.color);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([1.0, 0.9, 0.35, 1.0]), gl.DYNAMIC_DRAW);

    gl.bindBuffer(gl.ARRAY_BUFFER, selectedPoint.size);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([24.0]), gl.DYNAMIC_DRAW);
  }

  function pickFeature(x, y) {
    let bestIndex = -1;
    let bestDistance = Infinity;

    for (const projected of projectedFeatures) {
      if (!projected.screen.visible) {
        continue;
      }

      const dx = projected.screen.x - x;
      const dy = projected.screen.y - y;
      const distance = Math.hypot(dx, dy);
      if (distance < 18 && distance < bestDistance) {
        bestDistance = distance;
        bestIndex = projected.index;
      }
    }

    state.selectedIndex = bestIndex;
    updateSelectionPanel();
  }

  canvas.addEventListener('pointerdown', (event) => {
    state.dragging = true;
    state.lastX = event.clientX;
    state.lastY = event.clientY;
    canvas.setPointerCapture(event.pointerId);
  });

  canvas.addEventListener('pointermove', (event) => {
    state.mouseX = event.clientX;
    state.mouseY = event.clientY;
    if (!state.dragging) {
      return;
    }

    const dx = event.clientX - state.lastX;
    const dy = event.clientY - state.lastY;
    state.yaw += dx * 0.006;
    state.pitch = clamp(state.pitch + dy * 0.006, -1.35, 1.35);
    state.lastX = event.clientX;
    state.lastY = event.clientY;
  });

  canvas.addEventListener('pointerup', (event) => {
    if (!state.dragging) {
      return;
    }

    state.dragging = false;
    canvas.releasePointerCapture(event.pointerId);
    pickFeature(event.offsetX * deviceScale(), event.offsetY * deviceScale());
  });

  canvas.addEventListener('wheel', (event) => {
    event.preventDefault();
    state.distance = clamp(state.distance + event.deltaY * 0.002, 2.1, 6.0);
  }, { passive: false });

  toggleImagery.addEventListener('change', () => {});
  toggleFeatures.addEventListener('change', () => {
    if (!toggleFeatures.checked) {
      state.selectedIndex = -1;
      updateSelectionPanel();
    }
  });
  toggleRoutes.addEventListener('change', () => {});

  function deviceScale() {
    return Math.max(1, Math.min(window.devicePixelRatio || 1, 2));
  }

  updateSelectionPanel();
  requestAnimationFrame(render);

  function buildSphere(stacks, slices) {
    const positions = [];
    const normals = [];
    const uvs = [];
    const indices = [];

    for (let stack = 0; stack <= stacks; stack += 1) {
      const v = stack / stacks;
      const phi = v * Math.PI;
      const sinPhi = Math.sin(phi);
      const cosPhi = Math.cos(phi);

      for (let slice = 0; slice <= slices; slice += 1) {
        const u = slice / slices;
        const theta = u * Math.PI * 2;
        const sinTheta = Math.sin(theta);
        const cosTheta = Math.cos(theta);

        const x = sinPhi * cosTheta;
        const y = cosPhi;
        const z = sinPhi * sinTheta;

        positions.push(x, y, z);
        normals.push(x, y, z);
        uvs.push(u, 1 - v);
      }
    }

    for (let stack = 0; stack < stacks; stack += 1) {
      for (let slice = 0; slice < slices; slice += 1) {
        const first = stack * (slices + 1) + slice;
        const second = first + slices + 1;
        indices.push(first, second, first + 1, second, second + 1, first + 1);
      }
    }

    return {
      positions: new Float32Array(positions),
      normals: new Float32Array(normals),
      uvs: new Float32Array(uvs),
      indices: new Uint16Array(indices),
    };
  }

  function buildRoute(route, radius, segments) {
    const positions = [];
    const a = latLonToCartesian(route.start.lat, route.start.lon, 1.0);
    const b = latLonToCartesian(route.end.lat, route.end.lon, 1.0);

    for (let i = 0; i <= segments; i += 1) {
      const t = i / segments;
      const point = slerp(a, b, t, radius);
      positions.push(point[0], point[1], point[2]);
    }

    return {
      positions: new Float32Array(positions),
    };
  }

  function buildFeaturePoints(featureList, radius) {
    const positions = [];
    const colors = [];
    const sizes = [];

    for (const feature of featureList) {
      const world = latLonToCartesian(feature.lat, feature.lon, radius);
      positions.push(world[0], world[1], world[2]);
      colors.push(feature.color[0], feature.color[1], feature.color[2], feature.color[3]);
      sizes.push(14.0);
    }

    return {
      positions: new Float32Array(positions),
      colors: new Float32Array(colors),
      sizes: new Float32Array(sizes),
    };
  }

  function createImageryTexture(glContext) {
    const imageCanvas = document.createElement('canvas');
    imageCanvas.width = 1024;
    imageCanvas.height = 512;
    const ctx = imageCanvas.getContext('2d');

    const ocean = ctx.createLinearGradient(0, 0, 0, imageCanvas.height);
    ocean.addColorStop(0, '#0f2a52');
    ocean.addColorStop(1, '#051629');
    ctx.fillStyle = ocean;
    ctx.fillRect(0, 0, imageCanvas.width, imageCanvas.height);

    ctx.fillStyle = 'rgba(255, 255, 255, 0.03)';
    for (let x = 0; x < imageCanvas.width; x += 64) {
      ctx.fillRect(x, 0, 1, imageCanvas.height);
    }
    for (let y = 0; y < imageCanvas.height; y += 64) {
      ctx.fillRect(0, y, imageCanvas.width, 1);
    }

    paintContinent(ctx, [[120, 120], [170, 95], [250, 105], [290, 155], [260, 230], [180, 250], [130, 200]], '#2f7d49', '#1a4e31');
    paintContinent(ctx, [[220, 270], [260, 255], [290, 285], [280, 360], [250, 430], [220, 390], [200, 320]], '#4c8f4e', '#2b5934');
    paintContinent(ctx, [[430, 120], [520, 95], [620, 120], [690, 160], [660, 250], [560, 260], [470, 220]], '#6a8553', '#334932');
    paintContinent(ctx, [[500, 230], [560, 250], [590, 330], [540, 420], [480, 390], [450, 320]], '#557e45', '#2a4b2c');
    paintContinent(ctx, [[770, 260], [820, 245], [860, 280], [840, 340], [790, 330], [760, 290]], '#648a57', '#2f5130');
    paintContinent(ctx, [[80, 70], [120, 55], [160, 70], [145, 100], [100, 105]], '#8fb7b0', '#4c6e6b');

    ctx.fillStyle = 'rgba(255, 255, 255, 0.20)';
    ctx.font = 'bold 22px Inter, sans-serif';
    ctx.fillText('MIDGAARD IMAGERY', 32, 40);

    const texture = glContext.createTexture();
    glContext.bindTexture(glContext.TEXTURE_2D, texture);
    glContext.texImage2D(glContext.TEXTURE_2D, 0, glContext.RGBA, glContext.RGBA, glContext.UNSIGNED_BYTE, imageCanvas);
    glContext.texParameteri(glContext.TEXTURE_2D, glContext.TEXTURE_MIN_FILTER, glContext.LINEAR);
    glContext.texParameteri(glContext.TEXTURE_2D, glContext.TEXTURE_MAG_FILTER, glContext.LINEAR);
    glContext.texParameteri(glContext.TEXTURE_2D, glContext.TEXTURE_WRAP_S, glContext.CLAMP_TO_EDGE);
    glContext.texParameteri(glContext.TEXTURE_2D, glContext.TEXTURE_WRAP_T, glContext.CLAMP_TO_EDGE);
    return texture;
  }

  function paintContinent(ctx, points, fill, stroke) {
    ctx.beginPath();
    ctx.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i += 1) {
      ctx.lineTo(points[i][0], points[i][1]);
    }
    ctx.closePath();
    ctx.fillStyle = fill;
    ctx.fill();
    ctx.lineWidth = 4;
    ctx.strokeStyle = stroke;
    ctx.stroke();
  }

  function latLonToCartesian(latDeg, lonDeg, radius) {
    const lat = latDeg * Math.PI / 180;
    const lon = lonDeg * Math.PI / 180;
    const cosLat = Math.cos(lat);
    return [
      radius * cosLat * Math.cos(lon),
      radius * Math.sin(lat),
      radius * cosLat * Math.sin(lon),
    ];
  }

  function slerp(a, b, t, radius) {
    const dot = clamp(a[0] * b[0] + a[1] * b[1] + a[2] * b[2], -1, 1);
    const omega = Math.acos(dot);
    if (omega < 1e-5) {
      return [a[0] * radius, a[1] * radius, a[2] * radius];
    }

    const sinOmega = Math.sin(omega);
    const weightA = Math.sin((1 - t) * omega) / sinOmega;
    const weightB = Math.sin(t * omega) / sinOmega;
    const x = weightA * a[0] + weightB * b[0];
    const y = weightA * a[1] + weightB * b[1];
    const z = weightA * a[2] + weightB * b[2];
    const length = Math.hypot(x, y, z) || 1;
    return [radius * x / length, radius * y / length, radius * z / length];
  }

  function createArrayBuffer(glContext, data) {
    const buffer = glContext.createBuffer();
    glContext.bindBuffer(glContext.ARRAY_BUFFER, buffer);
    glContext.bufferData(glContext.ARRAY_BUFFER, data, glContext.STATIC_DRAW);
    return buffer;
  }

  function createProgram(glContext, vertexSource, fragmentSource) {
    const vertexShader = compileShader(glContext, glContext.VERTEX_SHADER, vertexSource);
    const fragmentShader = compileShader(glContext, glContext.FRAGMENT_SHADER, fragmentSource);
    const program = glContext.createProgram();
    glContext.attachShader(program, vertexShader);
    glContext.attachShader(program, fragmentShader);
    glContext.linkProgram(program);
    if (!glContext.getProgramParameter(program, glContext.LINK_STATUS)) {
      throw new Error(glContext.getProgramInfoLog(program) || 'Program link failed');
    }
    return program;
  }

  function compileShader(glContext, type, source) {
    const shader = glContext.createShader(type);
    glContext.shaderSource(shader, source);
    glContext.compileShader(shader);
    if (!glContext.getShaderParameter(shader, glContext.COMPILE_STATUS)) {
      throw new Error(glContext.getShaderInfoLog(shader) || 'Shader compile failed');
    }
    return shader;
  }

  function getLocations(glContext, program, attributes, uniforms) {
    const result = {};
    for (const name of attributes) {
      result[name] = glContext.getAttribLocation(program, name);
    }
    for (const name of uniforms) {
      result[name] = glContext.getUniformLocation(program, name);
    }
    return result;
  }

  function bindAttribute(glContext, location, buffer, size) {
    if (location < 0) {
      return;
    }
    glContext.bindBuffer(glContext.ARRAY_BUFFER, buffer);
    glContext.enableVertexAttribArray(location);
    glContext.vertexAttribPointer(location, size, glContext.FLOAT, false, 0, 0);
  }

  function orbitEye(yaw, pitch, distance) {
    const cosPitch = Math.cos(pitch);
    return [
      distance * cosPitch * Math.sin(yaw),
      distance * Math.sin(pitch),
      distance * cosPitch * Math.cos(yaw),
    ];
  }

  function projectPoint(viewProj, point, width, height) {
    const x = point[0];
    const y = point[1];
    const z = point[2];
    const clipX = viewProj[0] * x + viewProj[4] * y + viewProj[8] * z + viewProj[12];
    const clipY = viewProj[1] * x + viewProj[5] * y + viewProj[9] * z + viewProj[13];
    const clipZ = viewProj[2] * x + viewProj[6] * y + viewProj[10] * z + viewProj[14];
    const clipW = viewProj[3] * x + viewProj[7] * y + viewProj[11] * z + viewProj[15];

    if (clipW <= 0) {
      return { visible: false, x: 0, y: 0, depth: 1 };
    }

    const ndcX = clipX / clipW;
    const ndcY = clipY / clipW;
    return {
      visible: ndcX >= -1 && ndcX <= 1 && ndcY >= -1 && ndcY <= 1 && clipZ / clipW >= -1 && clipZ / clipW <= 1,
      x: (ndcX * 0.5 + 0.5) * width,
      y: (1 - (ndcY * 0.5 + 0.5)) * height,
      depth: clipZ / clipW,
    };
  }

  function mat4Perspective(fovy, aspect, near, far) {
    const f = 1.0 / Math.tan(fovy / 2);
    const nf = 1 / (near - far);
    return new Float32Array([
      f / aspect, 0, 0, 0,
      0, f, 0, 0,
      0, 0, (far + near) * nf, -1,
      0, 0, (2 * far * near) * nf, 0,
    ]);
  }

  function mat4LookAt(eye, center, up) {
    const zx = eye[0] - center[0];
    const zy = eye[1] - center[1];
    const zz = eye[2] - center[2];
    let length = Math.hypot(zx, zy, zz);
    const z0 = zx / length;
    const z1 = zy / length;
    const z2 = zz / length;

    const xx = up[1] * z2 - up[2] * z1;
    const xy = up[2] * z0 - up[0] * z2;
    const xz = up[0] * z1 - up[1] * z0;
    length = Math.hypot(xx, xy, xz);
    const x0 = xx / length;
    const x1 = xy / length;
    const x2 = xz / length;

    const y0 = z1 * x2 - z2 * x1;
    const y1 = z2 * x0 - z0 * x2;
    const y2 = z0 * x1 - z1 * x0;

    return new Float32Array([
      x0, y0, z0, 0,
      x1, y1, z1, 0,
      x2, y2, z2, 0,
      -(x0 * eye[0] + x1 * eye[1] + x2 * eye[2]),
      -(y0 * eye[0] + y1 * eye[1] + y2 * eye[2]),
      -(z0 * eye[0] + z1 * eye[1] + z2 * eye[2]),
      1,
    ]);
  }

  function mat4Multiply(a, b) {
    const out = new Float32Array(16);

    const a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3];
    const a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7];
    const a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
    const a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];

    let b0 = b[0], b1 = b[1], b2 = b[2], b3 = b[3];
    out[0] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
    out[1] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
    out[2] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
    out[3] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;

    b0 = b[4]; b1 = b[5]; b2 = b[6]; b3 = b[7];
    out[4] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
    out[5] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
    out[6] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
    out[7] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;

    b0 = b[8]; b1 = b[9]; b2 = b[10]; b3 = b[11];
    out[8] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
    out[9] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
    out[10] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
    out[11] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;

    b0 = b[12]; b1 = b[13]; b2 = b[14]; b3 = b[15];
    out[12] = b0 * a00 + b1 * a10 + b2 * a20 + b3 * a30;
    out[13] = b0 * a01 + b1 * a11 + b2 * a21 + b3 * a31;
    out[14] = b0 * a02 + b1 * a12 + b2 * a22 + b3 * a32;
    out[15] = b0 * a03 + b1 * a13 + b2 * a23 + b3 * a33;

    return out;
  }

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
  }
})();
