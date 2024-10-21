mdp

const init_pod; const init_demand; const init_pow;
const init_rt; const TAU=2;	//initial number of pods, utilization, response time, period duration

//demand follow number of pods in datasets
const demand_a=init_demand; 
const demand_b=init_demand; 
const demand_c=init_demand; 
const demand_d=init_demand; 
const demand_e=init_demand; 
const demand_f=init_demand;
const util_a=30; const util_b=48; const util_c=59; 
const util_d=73; const util_e=85; const util_f=95; 	  							//new utilization after request is added
const lat_a=2; const lat_b=3; const lat_c=4; 
const lat_d=5; const lat_e=6; const lat_f=7;
const pow_a=245; const pow_b=270; const pow_c=295;
const pow_d=344; const pow_e=370; const pow_f=394;

const maxDemand=limitPod;	//max Demand
const minPod=1;		//min threshold of pods
const maxPod;		//max threshold of pods
const limitPod;		//pod limit
const maxLat=10;		//maximum latency (s)
const maxRt=5;		//maximum response time (s)
const maxTime;		//maximum timestep (s)
const maxPower=249;	//maximum power (W)
const idlePower=170;	//idle power (W)
const up_rt=2;		//updated response time (s)
const cpu_request;	//cpu core request by pod
const target_util=50;

//const i_util=ceil(init_util/cpu_request);	//initial utilization of pods
formula u_util=ceil(u/cpu_request);		//updated utilization of pods after scaling
formula desired_replica = ceil(pod*(u/target_util)); //https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

formula power=idlePower+((u/100)*maxPower);
formula power2=idlePower+((u2/100)*maxPower);
formula power_overall=idlePower+((avg_util/100)*maxPower);

formula avg_util = ceil((u+u2)/2);


//performance ratio change @ scalability
formula tw = t;
formula cr = pod;
formula tw2 = maxTime;
formula cr2 = maxPod;

formula prr1 = (1/(tw*cr));
formula prr2 = (1/(tw2*cr2));
formula ratio = ((prr1*demand)/(prr2*maxDemand));


module pod_demand
	//rate of incoming load per sec
	demand:[0..maxDemand] init demand_a;
	//number of pods in the app.
	pod:[0..limitPod] init init_pod;
	//utilization associated with the demand
	ud:[0..100] init 0;
	//latency of the app.
	l:[-1..maxLat] init 5;

	[do_not] true -> (pod'=current_pod) & (ud'=util);

	[] pod>0 & pod<=50 ->0.185:(demand'=demand)&(l'=lat_a)&(ud'=util_a)  
				+ 0.630:(demand'=demand_b)&(l'=lat_b)&(ud'=util_b) 
		 	 	+ 0.185:(demand'=demand_c)&(l'=lat_c)&(ud'=util_c); 

	[] pod>50 & pod<=limitPod ->0.185:(demand'=demand_d)&(l'=lat_d)&(ud'=util_d)
				+ 0.630:(demand'=demand_e)&(l'=lat_e)&(ud'=util_e)
		 	 	+ 0.185:(demand'=demand_f)&(l'=lat_f)&(ud'=util_f); 
endmodule

module metric_server
	cpu: [0..100] init 1;

	[do_not] true -> (cpu'= avg_util); //& (pod_m'= avg_pod);
endmodule

module kubelet
	//utilization of the app. after add certain amount of demand
	u: [0..100] init 1;
	pow:[0..1000000] init init_pow;

	[do_not] true -> (u'=ud) & (pow'=ceil(power));
	
endmodule

module kubelet2
	//latency of the app.
	//l:[-1..maxLat] ;
	//utilization of the app. after add certain amount of demand
	u2: [0..100] init 1;
	pow2:[0..1000000] init init_pow;

	[do_not] true -> (u2'=ud) & (pow2'=ceil(power+50));
	
endmodule



module autoscaler
	//updated number of pods in the app.
	current_pod:[minPod..maxPod] init minPod;
	//current pod utilization by the app.
	util:[0..100] init 30;
	//time step
	t: [0..maxTime] init 0;
	//response time
	rt:[0..maxTime] init init_rt;
	//update latency
	lat:[-1..maxLat] init 5;
	//action(act) : 0-add VM, 1-remove VM, 2-do nothing, 3 start
	act:[0..3] init 3;
	
	//(default behavior) : https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#default-behavior

	//cpu util
	[scale_out] (60>=u & u<=100) & act!=1 & (pod<desired_replica) & (t+TAU<maxTime) -> 1/2:(current_pod'=desired_replica<maxPod?pod+pod:maxPod)
							&(t'=t+TAU)&(util'=u>util? u_util:util)&(act'=0) + 1/2:(current_pod'=desired_replica<40?pod+4:pod+pod)
							&(t'=t+TAU)&(util'=u>util? u_util:util)&(act'=0);

	[do_not] (40>=u & u<60) | (t=maxTime)| (current_pod=maxPod) | (current_pod=desired_replica) -> (current_pod'=current_pod)&(act'=2);

	[scale_in] (0>=u & u<60) & act!=0  & (pod>maxPod) & (t+TAU<maxTime) -> (current_pod'=desired_replica<minPod?minPod:minPod)&(t'=t+TAU)&(util'=u>util? u_util:util)&(act'=1);


	//latency & response time
	[] pod<=maxPod & (l!=0) -> (lat'=l>0?l-1:lat);

	[scale_in] pod>0 & (lat=0) & act!=0 & (rt<maxRt) & (t+TAU<maxTime) -> 
	(current_pod'=desired_replica<minPod?minPod:minPod)&(lat'=-1)&(t'=t+TAU)&(util'=u>util? u_util:util)&(act'=1);
	
	[scale_out] (lat=-1) & l>0 & act!=1 & (rt>maxRt) & (t+TAU<maxTime)-> 1/2:(current_pod'=desired_replica<maxPod?pod+pod:maxPod)&(lat'=l>0?l-1:lat)&(rt'=up_rt)&(util'=u>util? u_util:util)&(t'=t+TAU)&(act'=0)
		+1/2:(current_pod'=desired_replica<40?pod+4:pod+pod)&(lat'=l>0?l-1:lat)&(rt'=up_rt)&(util'=u>util? u_util:util)&(t'=t+TAU)&(act'=0);

endmodule


rewards "performance_change"
	ratio>=0 & ratio<10: ratio;
endrewards


rewards "energy_consumption"
	[scale_out] current_pod=desired_replica | current_pod<=maxPod : power_overall;
	[scale_in] current_pod=desired_replica | current_pod<=maxPod : power_overall;
	[do_not] current_pod=desired_replica | current_pod<=maxPod : power_overall;
endrewards

rewards "energy_vio"
	[scale_out] pod<desired_replica & power>maxPower:1;
	[scale_in] pod<desired_replica & power>maxPower:1;
	[do_not] pod<desired_replica & power>maxPower:1;
endrewards

rewards "desired_replica"
	current_pod = desired_replica : desired_replica;
endrewards