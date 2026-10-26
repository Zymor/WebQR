import {randomBytes,randomUUID,createHash,scrypt as scryptCb,timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';
const scrypt=promisify(scryptCb);
export class Problem extends Error{constructor(message,status=400){super(message);this.status=status;}}
export const hash=(s)=>createHash('sha256').update(s).digest('hex');
export const id=(prefix)=>prefix+randomBytes(6).toString('hex').toUpperCase();
export const secret=()=>randomBytes(32).toString('base64url');
export async function passwordHash(password){const salt=randomBytes(16).toString('hex');return salt+':'+(await scrypt(password,salt,64)).toString('hex');}
export async function passwordMatches(password,value){try{const [salt,key]=value.split(':');const actual=await scrypt(password,salt,64);return timingSafeEqual(actual,Buffer.from(key,'hex'));}catch{return false;}}
export function text(data,key,min=0,max=1000){const value=String(data[key]??'').trim();if(value.length<min||value.length>max)throw new Problem(`${key}: enter ${min}–${max} characters.`);return value;}
export function integer(value,min,max,name='quantity'){if(!Number.isSafeInteger(value)||value<min||value>max)throw new Problem(`${name} must be a whole number from ${min} to ${max}.`);return value;}
const transitions={new:['accepted','rejected','cancelled'],accepted:['preparing','cancelled'],preparing:['ready','cancelled'],ready:['served'],served:['completed']};
export function validateTransition(from,to,reason){if(!transitions[from]?.includes(to))throw new Problem(`Cannot move an order from ${from} to ${to}.`,409);if(['rejected','cancelled'].includes(to)&&!reason.trim())throw new Problem('Please provide a rejection or cancellation reason.');}
export function address(value){const s=String(value??'').trim().toLowerCase();if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s)||s.length>254)throw new Problem('Enter a valid email address.');return s;}
export const uuid=randomUUID;
