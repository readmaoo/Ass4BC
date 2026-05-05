import "../styles/Delegation.css"
export default function Delegation(){
    return(
        <div className="deleget">
        <h2 id="dl">Delegation</h2>
        <p>Delegate Votes to address</p>
        <input placeholder="0x..." id="adr"></input>
        <button id="but">Delegate</button>
        </div>
    )
}