import numpy as np

cimport cython
cimport openctm
cimport numpy as np

cdef class CTMfile:
	cdef CTMcontext ctx

	cdef public bytes filename
	cdef public str mode
	cdef public str method
	cdef public int complevel

	cdef unsigned int length
	cdef object pts
	cdef object polys
	cdef object norms
	cdef dict attribs
	cdef dict uvs

	def __cinit__(self, bytes filename, str mode='r'):
		cdef openctm.CTMenum err
		self.filename = filename
		self.mode = mode
		self.attribs = {}
		self.uvs = {}

		if mode == 'r':
			self.ctx = openctm.ctmNewContext(openctm.CTM_IMPORT)
			openctm.ctmLoad(self.ctx, self.filename)
			err = ctmGetError(self.ctx)
			if err != openctm.CTM_NONE:
				raise IOError(openctm.ctmErrorString(err))

		elif mode == 'w':
			self.ctx = openctm.ctmNewContext(openctm.CTM_EXPORT)
			self.length = 0
		else:
			raise IOError

	def __dealloc__(self):
		if self.ctx is not NULL:
			openctm.ctmFreeContext(self.ctx)

	def __len__(self):
		return self.length

	def setMesh(self, object[np.double_t, ndim=2] pts, object[np.uint32_t, ndim=2] polys, object[np.double_t, ndim=2] norms = None):
		if self.mode == "r":
			raise IOError
		if self.length == 0:
			self.length = len(pts)
		elif self.length != len(pts):
			raise TypeError('Invalid number of vertices')

		self.pts = np.ascontiguousarray(pts).astype(np.float32)
		self.polys = np.ascontiguousarray(polys).astype(np.uint32)

		if norms is not None:
			self.norms = np.ascontiguousarray(norms).astype(np.float32)

	def addAttrib(self, object[np.double_t, ndim=2] attrib, str name=None):
		if self.mode == "r":
			raise IOError
		if self.length == 0:
			self.length = len(attrib)
		elif self.length != len(attrib):
			raise TypeError('Invalid attribute length')

		if name is None:
			name = 'attrib_%d'%len(self.attribs)
		self.attribs[name] = np.ascontiguousarray(attrib).astype(np.float32)

	def addUV(self, object[np.double_t, ndim=2] uv, str name=None, str filename=None):
		if self.mode == "r":
			raise IOError
		if self.length == 0:
			self.length = len(uv)
		elif self.length != len(uv):
			raise TypeError('Invalid UV length')

		if name is None:
			name = 'uv_%d'%len(self.uvs)
		self.uvs[name] = filename, np.ascontiguousarray(uv).astype(np.float32)

	@cython.boundscheck(False)
	def getMesh(self):
		if self.mode == "w":
			raise IOError

		cdef unsigned int i
		cdef unsigned int npts = openctm.ctmGetInteger(self.ctx, CTM_VERTEX_COUNT)
		cdef unsigned int npolys = openctm.ctmGetInteger(self.ctx, CTM_TRIANGLE_COUNT)
		cdef np.ndarray pts = np.zeros((npts, 3), dtype=np.float32)
		cdef np.ndarray polys = np.zeros((npolys, 3), dtype=np.uint32)
		cdef object norms = None

		cdef float* cpts = openctm.ctmGetFloatArray(self.ctx, CTM_VERTICES)
		cdef unsigned int* cpolys = openctm.ctmGetIntegerArray(self.ctx, CTM_INDICES)

		for i in range(npts):
			pts[i, 0] = cpts[i*3]
			pts[i, 1] = cpts[i*3+1]
			pts[i, 2] = cpts[i*3+2]

		for i in range(npolys):
			polys[i, 0] = cpolys[i*3]
			polys[i, 1] = cpolys[i*3+1]
			polys[i, 2] = cpolys[i*3+2]

		return pts, polys, norms

	def save(self, str method='mg2', int complevel=9):
		cdef float* cnorms
		cdef openctm.CTMenum err
		cdef openctm.CTMenum ctmmeth

		cdef np.ndarray[np.float32_t, ndim=2] pts
		cdef np.ndarray[np.uint32_t, ndim=2] polys
		cdef np.ndarray[np.float32_t, ndim=2] norms
		cdef char *cname

		if self.norms is not None:
			norms = self.norms
			cnorms = <float*>norms.data

		if method == "mg2":
			ctmmeth = openctm.CTM_METHOD_MG2
		elif method == "mg1":
			ctmmeth = openctm.CTM_METHOD_MG1
		elif method == "raw":
			ctmmeth = openctm.CTM_METHOD_RAW
		else:
			raise TypeError('Invalid compression method')

		openctm.ctmCompressionMethod(self.ctx, ctmmeth)
		err = openctm.ctmGetError(self.ctx)
		if err != openctm.CTM_NONE:
			raise Exception(openctm.ctmErrorString(err))

		if method != "raw":
			openctm.ctmCompressionLevel(self.ctx, complevel)
			err = openctm.ctmGetError(self.ctx)
			if err != openctm.CTM_NONE:
				raise Exception(openctm.ctmErrorString(err))

		pts = self.pts
		polys = self.polys
		print pts.data[0], pts.data[1], pts.data[2]
		openctm.ctmDefineMesh(self.ctx, <float*>pts.data, self.length, 
			<unsigned int*> polys.data, <unsigned int>len(self.polys), cnorms)

		err = openctm.ctmGetError(self.ctx)
		if err != openctm.CTM_NONE:
			raise Exception(openctm.ctmErrorString(err))

		for name, attrib in self.attribs.items():
			pts = attrib
			err = openctm.ctmAddAttribMap(self.ctx, <float*> pts.data, <char*>cname)
			if err == openctm.CTM_NONE:
				err = openctm.ctmGetError(self.ctx)
				raise Exception(openctm.ctmErrorString(err))

		for name, (fname, uv) in self.uvs.items():
			if fname is not None:
				cname = fname
			pts = uv
			err = openctm.ctmAddUVMap(self.ctx, <float*>pts.data, <char*>cname, cname)
			if err == openctm.CTM_NONE:
				err = openctm.ctmGetError(self.ctx)
				raise Exception(openctm.ctmErrorString(err))

		openctm.ctmSave(self.ctx, self.filename)
		err = openctm.ctmGetError(self.ctx)
		if err != openctm.CTM_NONE:
			raise Exception(openctm.ctmErrorString(err))
