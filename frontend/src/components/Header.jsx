import "../styles/Header.css"
import { ethers } from "ethers";
import { useState } from "react";
export default function Header({onActive}){
    let signer = null;
    let provider;
    const [address, setAddress] = useState("");
    async function ConnectMetamask(){
        if (window.ethereum == null) {
            console.log("MetaMask not installed; using read-only defaults")
            provider = ethers.getDefaultProvider()
        } else {
            provider = new ethers.BrowserProvider(window.ethereum)
            signer = await provider.getSigner();
            const userAddress = await signer.getAddress();
            setAddress(userAddress);
            onActive();
        }
    }
    return(
    <div className="Header">
    <h2 id="name">Simplified DAO Governance dApp</h2>
    <div className="auth-container">
            <button id="metamask" onClick={ConnectMetamask}>
                {address ? "CONNECTED" : "CONNECT METAMASK"}
            </button>
            {address && <p id="addr"> Your address: {address}</p>}
        </div>
    </div>
    )
}