#version 430


in VertexOutput
{
	vec4 position;
	int multiplicity;

} IN;

out int multiplicity;  //color?

void main()
{

	//if(gl_FrontFacing == true){
	multiplicity = IN.multiplicity;	//by activating blending all should be added
	//}
	//disable depth test?
}
