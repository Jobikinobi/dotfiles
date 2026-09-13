const e=t=>!t.heartbeat||!t.heartbeatTTL?!1:new Date(t.heartbeat).getTime()+(t.heartbeatTTL+30)*1e3>Date.now();export{e as i};
