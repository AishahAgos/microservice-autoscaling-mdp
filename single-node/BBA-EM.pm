mdp

//declaration
const init_pod; const init_cpu;  const init_demand; const init_pow; const init_lat; const init_rt; 

//initialization
const TAU=2;													//initial number of pods, utilization, response time, period duration
const util_a=30; const util_b=48; const util_c=59; const util_d=73; const util_e=85; const util_f=95; 	  							//new utilization after request is added
const lat_a=2; const lat_b=3; const lat_c=4; const lat_d=5; const lat_e=6; const lat_f=7;
const pow_a=245; const pow_b=270; const pow_c=295; const pow_d=344; const pow_e=370; const pow_f=394;

const maxDemand=1000;	//max Demand
const minPod=1;		//min threshold of pods
const maxPod;		//max threshold of pods
const limitPod=1000;	//pod limit
const maxLat=10;	//maximum latency (s)
const maxRt=5;		//maximum response time (s)
const maxTime=1000;	//maximum timestep (s)
const maxPower=249;	//maximum power (W)
const idlePower=170;	//idle power (W)
const up_rt=2;		//updated response time (s)
const cpu_request=3;	//cpu request by pod
const target_util=50;

//formula CPU utilization, desired replica, power
formula u_util=ceil(u/cpu_request);											//updated utilization of pods after scaling
formula desired_replica = ceil(pod*(u/target_util)); 											//https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
formula power=idlePower+((u/100)*maxPower);

//performance-resource ratio(PRR), scalability
formula tw = t; formula cr = pod; formula tw2 = maxTime; formula cr2 = maxPod;
formula prr1 = (1/(tw*cr)); formula prr2 = (1/(tw2*cr2));
formula ratio = ((prr1*demand)/(prr2*maxDemand));



module kubelet
	//rate of incoming load per sec
	demand:[0..maxDemand] init init_demand;
	//number of pods in the app.
	pod:[0..limitPod] init init_pod;
	//latency of the app.
	l:[-1..maxLat] ;
	//utilization of the app. after add certain amount of demand
	u: [0..100] init 0;
	pow:[0..1000000] init init_pow;

	[do_not] true -> (pod'=current_pod) & (u'=util) & (pow'=ceil(power));

	[] pod>0 & pod<=50 ->0.185:(demand'=demand)&(l'=lat_a)&(u'=util_a)&(pow'=pow)  
				+ 0.630:(demand'=demand)&(l'=lat_b)&(u'=util_b)&(pow'=pow_b) 
		 	 	+ 0.185:(demand'=demand)&(l'=lat_c)&(u'=util_c)&(pow'=pow_c); 

	[] pod>50 & pod<=limitPod ->0.185:(demand'=demand)&(l'=lat_d)&(u'=util_d)&(pow'=pow)
				+ 0.630:(demand'=demand)&(l'=lat_e)&(u'=util_e)&(pow'=pow_e)
		 	 	+ 0.185:(demand'=demand)&(l'=lat_f)&(u'=util_f)&(pow'=pow_f); 
endmodule



module autoscaler
	//updated number of pods in the app.
	current_pod:[minPod..maxPod] init minPod;
	//current pod utilization by the app.
	util:[0..100] init init_cpu;
	//time step
	t: [0..maxTime] init 0;
	//action(act) : 0-add VM, 1-remove VM, 2-do nothing, 3 start
	act:[0..3] init 3;
	//response time
	rt:[0..maxTime] init init_rt;
	//update latency
	lat:[-1..maxLat] init init_lat;
	
	//cpu util
	[scale_out] (60>=u & u<=100) & act!=1 & (pod<desired_replica) & (t+TAU<maxTime) -> 1/2:(current_pod'=desired_replica<maxPod?pod+pod:maxPod)
							&(t'=t+TAU)&(util'=u>util? u_util:util)&(act'=0) + 1/2:(current_pod'=desired_replica<40?pod+4:pod+pod)
							&(t'=t+TAU)&(util'=u>util? u_util:util)&(act'=0);

	[do_not] (40>=u & u<60) | (current_pod=maxPod) | (current_pod=desired_replica) -> (current_pod'=current_pod)&(act'=2);

	[scale_in] (0>=u & u<60) & act!=0  & (pod>maxPod) & (t+TAU<maxTime) -> (current_pod'=desired_replica<minPod?minPod:minPod)&(t'=t+TAU)&(util'=u>util? u_util:util)&(act'=1);


	//energy
	[scale_in] (pow>maxPower) & act!=0& (pod>maxPod) & (t+TAU<maxTime) -> (current_pod'=desired_replica<minPod?minPod:minPod)&(t'=t+TAU)&(util'=u>util? u_util:util)&(act'=1);
	[scale_in] (power>300) & act!=0 & (current_pod>maxPod) & (t+TAU<maxTime) -> (current_pod'=desired_replica<minPod?minPod:minPod)&(t'=t+TAU)&(util'=u>util? u_util:util)&(act'=1);

endmodule

rewards "performance_change"
	ratio>=0 & ratio<10: ratio;
endrewards


rewards "energy_consumption"
	[scale_out] current_pod=desired_replica | current_pod<=maxPod : power;
	[scale_in] current_pod=desired_replica | current_pod<=maxPod : power;
	[do_not] current_pod=desired_replica | current_pod<=maxPod : power;
endrewards

rewards "energy_vio"
	[scale_out] pod<desired_replica & power>maxPower:1;
	[scale_in] pod<desired_replica & power>maxPower:1;
	[do_not] pod<desired_replica & power>maxPower:1;
endrewards

rewards "desired_replica"
	current_pod = desired_replica : desired_replica;
endrewards