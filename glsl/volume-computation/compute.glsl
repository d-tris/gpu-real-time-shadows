#version 430

layout (local_size_x = 128) in;

uniform uint indexCount;
uniform uint indexOffset;
uniform vec3 lightDir = vec3(-1.0, -1.0, -1.0);
uniform float extrusionDistance = 100.0;

struct InVertex
{
	float x;
	float y;
	float z;
	float nx;
	float ny;
	float nz;
	float u;
	float v;
};

struct OutVertex
{
	vec4 position;
	uint multiplicity;
	uint isCap;
	uint padding0;
	uint padding1;
};

layout (std430, binding = 0) readonly buffer InVertices
{
	InVertex inVertices[];
};

layout (std430, binding = 1) readonly buffer InIndices
{
	uint inIndices[];
};

layout (std430, binding = 2) writeonly buffer OutVertices
{
	OutVertex outVertices[];
};

layout (std430, binding = 3) writeonly buffer OutInfo
{
	uint outTriCount;
};

vec3 position(InVertex vert)
{
	return vec3(vert.x, vert.y, vert.z);
}

bool isFrontFacing(vec3 a, vec3 b, vec3 c)
{
	vec3 ab = b - a;
	vec3 ac = c - a;
	vec3 n = cross(ab, ac);
	return dot(normalize(n), normalize(lightDir)) > 0;
	//return a.x > 0 && b.x > 0 && c.x > 0;
}

// Rezervuje trojuhelniky pro emitTriangle. Vhodne pro n > 1.
uint reserveTriangles(uint n)
{
	return atomicAdd(outTriCount, n);
}

void emitTriangle(uint idx, vec3 a, vec3 b, vec3 c, uint multiplicity, uint isCap)
{
	idx *= 3;
	
	OutVertex outVertex;
	outVertex.multiplicity = multiplicity;
	outVertex.isCap = isCap;
	
	outVertex.position = vec4(a, 1.0);
	outVertices[idx] = outVertex;
	outVertex.position = vec4(b, 1.0);
	outVertices[idx + 1] = outVertex;
	outVertex.position = vec4(c, 1.0);
	outVertices[idx + 2] = outVertex;
}

// zjisti, zda je bod point pred nebo za rovinou definovanou body a, b a c
bool isInFront(vec3 point, vec3 a, vec3 b, vec3 c)
{
	vec3 ab = b - a;
	vec3 ac = c - a;
	
	vec3 normal = normalize(cross(ab, ac));
	vec3 pointvec = normalize(point - a);
	return dot(normal, pointvec) > 0; // TODO mozna prehodit za <
}

void main()
{
	uint triangleId = gl_GlobalInvocationID.x;
	if (triangleId * 3 < indexCount)
	{
		uint firstIdx = indexOffset + triangleId * 3;
		
		uint aidx[3];
		aidx[0] = inIndices[firstIdx];
		aidx[1] = inIndices[firstIdx + 1];
		aidx[2] = inIndices[firstIdx + 2];
		vec3 a0 = position(inVertices[aidx[0]]);
		vec3 a1 = position(inVertices[aidx[1]]);
		vec3 a2 = position(inVertices[aidx[2]]);
		
		vec3 extrusionVec = extrusionDistance * normalize(lightDir);
		
		if (isFrontFacing(a0, a1, a2))
		{
			uint triIdx = reserveTriangles(2);
			emitTriangle(triIdx, a0, a1, a2, 1, 1);
			emitTriangle(triIdx + 1, a0 + extrusionVec, a2 + extrusionVec, a1 + extrusionVec, 1, 1);	
		}
		
		uint edgeIndices[] = {aidx[0], aidx[1], aidx[1], aidx[2], aidx[2], aidx[0]};
		uint edgeMultiplicity[] = {0, 0, 0};
		
		for (uint triIdx = 0; triIdx < indexCount; triIdx += 3)
		{
			for (uint edgeIdx = 0; edgeIdx < 3; edgeIdx++)
			{
				uint thisEdge[2];
				thisEdge[0] = edgeIndices[edgeIdx * 2];
				thisEdge[1] = edgeIndices[edgeIdx * 2 + 1];
				
				uint bidx[3];
				bidx[0] = inIndices[triIdx + indexOffset];
				bidx[1] = inIndices[triIdx + 1 + indexOffset];
				bidx[2] = inIndices[triIdx + 2 + indexOffset];
			
				uint matchingVertices = 0;
				uint thirdVertIdx = 0;
				for (uint otherVertIdx = 0; otherVertIdx < 3; otherVertIdx++)
				{
					if (thisEdge[0] == bidx[otherVertIdx]
						|| thisEdge[1] == bidx[otherVertIdx])
					{
						matchingVertices++;
					}
					else
					{
						// nenasli jsme rovnocenny vertex v trojuhelniku,
						// takze bud tento trojuhelnik nesdili tuto hranu
						// a nebo sdili a tento vertex je treti nesdileny
						thirdVertIdx = bidx[otherVertIdx];
					}
				}
				
				if (matchingVertices == 2)
				{
					// kazdou hranu zpracovava trojuhelnik s nejnizsim indexem
					if (triIdx < triangleId * 3) break;
					
					vec3 edge0 = position(inVertices[thisEdge[0]]);
					vec3 edge1 = position(inVertices[thisEdge[1]]);
					vec3 thirdVert = position(inVertices[thirdVertIdx]);
				
					edgeMultiplicity[edgeIdx] += isInFront(thirdVert, edge0, edge1, edge1 + lightDir) ? 1 : -1;
				}
			}
		}
		
		for (uint edgeIdx = 0; edgeIdx < 3; edgeIdx++)
		{
			if (edgeMultiplicity[edgeIdx] != 0)
			{
				vec3 edge0 = position(inVertices[edgeIndices[edgeIdx * 2]]);
				vec3 edge1 = position(inVertices[edgeIndices[edgeIdx * 2 + 1]]);
				
				uint triIdx = reserveTriangles(2);
				emitTriangle(triIdx, edge0, edge1, edge0 + extrusionVec, edgeMultiplicity[edgeIdx], 0);
				emitTriangle(triIdx + 1, edge1, edge1 + extrusionVec, edge0 + extrusionVec, edgeMultiplicity[edgeIdx], 0);
			}
		}
	}
}
