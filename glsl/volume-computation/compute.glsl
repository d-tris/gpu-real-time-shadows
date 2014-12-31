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
	int padding;
};

struct OutVertex
{
	vec4 position;
	int multiplicity;
	uint isCap;
	uint padding0;
	uint padding1;
};

struct SimpleVertex
{
	vec4 position;
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

layout (std430, binding = 4) buffer VertexSortBuffer
{
	SimpleVertex sortBuffer[];
};

layout (std430, binding = 5) buffer IdxRemapBuffer
{
	uint idxRemapBuffer[];
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
	return dot(normalize(n), normalize(lightDir)) < 0;
	//return a.x > 0 && b.x > 0 && c.x > 0;
}

// Rezervuje trojuhelniky pro emitTriangle. Vhodne pro n > 1.
uint reserveTriangles(uint n)
{
	return atomicAdd(outTriCount, n);
}

void emitTriangle(uint idx, vec3 a, vec3 b, vec3 c, int multiplicity, uint isCap)
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
	return dot(pointvec, normal) > 0.0;
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
			emitTriangle(triIdx, a0, a1, a2, -1, 1);
			emitTriangle(triIdx + 1, a0 + extrusionVec, a2 + extrusionVec, a1 + extrusionVec, -1, 1);	
		}
		
		uint edgeIndices[] = {aidx[0], aidx[1], aidx[1], aidx[2], aidx[2], aidx[0]};
		int edgeMultiplicity[] = {0, 0, 0};
		bool ignoredEdge[] = {false, false, false};
		
		for (uint idxIdx = 0; idxIdx < indexCount; idxIdx += 3)
		{
			for (uint edgeIdx = 0; edgeIdx < 3; edgeIdx++)
			{
				if (!ignoredEdge[edgeIdx])
				{
					uint thisEdge[2];
					thisEdge[0] = edgeIndices[edgeIdx * 2];
					thisEdge[1] = edgeIndices[edgeIdx * 2 + 1];
					
					uint bidx[3];
					bidx[0] = inIndices[idxIdx + indexOffset];
					bidx[1] = inIndices[idxIdx + 1 + indexOffset];
					bidx[2] = inIndices[idxIdx + 2 + indexOffset];
				
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
						if (idxIdx < triangleId * 3)
						{
							ignoredEdge[edgeIdx] = true;
							break;
						}
						
						vec3 edge0 = position(inVertices[thisEdge[0]]);
						vec3 edge1 = position(inVertices[thisEdge[1]]);
						vec3 thirdVert = position(inVertices[thirdVertIdx]);
					
						edgeMultiplicity[edgeIdx] += isInFront(thirdVert, edge0, edge1, edge1 + lightDir) ? -1 : 1;
					}
				}
			}
		}
		
		for (uint edgeIdx = 0; edgeIdx < 3; edgeIdx++)
		{
			if (!ignoredEdge[edgeIdx] && edgeMultiplicity[edgeIdx] != 0)
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
