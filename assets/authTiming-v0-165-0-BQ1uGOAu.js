const e=async(t,a)=>{const o=Math.max(0,a-(Date.now()-t));o>0&&await new Promise(s=>{setTimeout(s,o)})},n=t=>e(t,500);export{n as w};
