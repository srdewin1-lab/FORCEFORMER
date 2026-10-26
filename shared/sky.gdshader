shader_type sky;
uniform vec3 sun_direction = vec3(0.,1.,0.);
uniform vec3 rise_direction = vec3(-1.,0.,0.);
uniform vec3 night_colour = vec3(.035,.06,.13);
uniform vec3 day_colour = vec3(.35,.42,.55);
uniform float day_energy = 1.;
uniform float predawn = 0.;
uniform float disc_scale = 1.;
uniform bool disc_visible = true;
void sky(){
 float daylight = smoothstep(-.10,.18,sun_direction.y)*day_energy;
 float horizon = pow(1.-abs(EYEDIR.y),5.);
 vec3 atmosphere = mix(night_colour,day_colour,clamp(daylight,0.,1.));
 float disc = smoothstep(cos(.07*disc_scale),cos(.055*disc_scale),dot(EYEDIR,sun_direction));
 // Extended dune geometry supplies the horizon and occludes the sun disc.
 vec3 sun_bearing = normalize(vec3(sun_direction.x,.001,sun_direction.z));
 float twilight = (1.-smoothstep(.02,.22,abs(sun_direction.y)))*horizon;
 float warm_horizon = pow(max(0.,dot(normalize(vec3(EYEDIR.x,.001,EYEDIR.z)),sun_bearing)),10.)*twilight;
 float dawn = pow(max(0.,dot(normalize(vec3(EYEDIR.x,.001,EYEDIR.z)),rise_direction)),8.)*horizon*predawn;
 COLOR = atmosphere*(.75+.25*horizon)+vec3(.19,.055,.015)*warm_horizon+vec3(.1,.04,.015)*dawn;
 vec3 sun_colour = mix(vec3(1.,.42,.16),vec3(1.,.90,.67),smoothstep(0.,.20,sun_direction.y));
 if(disc_visible) COLOR += sun_colour*disc*2.;
}
