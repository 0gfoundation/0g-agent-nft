// direct-rpc-clear.ts
import { ethers } from "ethers";
import dotenv from "dotenv";
dotenv.config();

async function directRPCClear() {
    console.log("=== Direct RPC Clear (Bypass Hardhat) ===");
    
    const provider = new ethers.JsonRpcProvider("https://evmrpc-testnet.0g.ai");
    
    if (!process.env.ZG_AGENT_NFT_BOB_PRIVATE_KEY) {
        throw new Error("ZG_TESTNET_PRIVATE_KEY environment variable not set");
    }
    
    const wallet = new ethers.Wallet(process.env.ZG_AGENT_NFT_BOB_PRIVATE_KEY, provider);
    console.log("Wallet address:", wallet.address);
    
    const latestNonce = await provider.getTransactionCount(wallet.address, "latest");
    const pendingNonce = await provider.getTransactionCount(wallet.address, "pending");
    
    console.log("Latest nonce:", latestNonce, `(0x${latestNonce.toString(16)})`);
    console.log("Pending nonce:", pendingNonce, `(0x${pendingNonce.toString(16)})`);
    
    const stuckCount = pendingNonce - latestNonce;
    console.log("Stuck transactions:", stuckCount);
    
    if (stuckCount === 0) {
        console.log("✅ No stuck transactions found");
        return;
    }
    
    console.log(`🔧 Clearing ${stuckCount} stuck transactions...`);
    console.log(`Will replace nonces ${latestNonce} to ${pendingNonce - 1}`);
    
    for (let i = 0; i < stuckCount; i++) {
        const nonce = latestNonce + i;
        console.log(`\n🚀 Clearing nonce ${nonce} (0x${nonce.toString(16)})...`);
        
        try {
            const tx = await wallet.sendTransaction({
                to: wallet.address,
                value: 0,
                nonce: nonce,
                maxFeePerGas: ethers.parseUnits("120", "gwei"),
                maxPriorityFeePerGas: ethers.parseUnits("25", "gwei"),
                gasLimit: 21000
            });
            
            console.log(`✅ Replacement transaction sent: ${tx.hash}`);
            
            // console.log("⏳ Waiting for confirmation...");
            // await tx.wait(1);
            // console.log("✅ Confirmed");
            
        } catch (error: any) {
            console.log(`❌ Failed to clear nonce ${nonce}:`, error.message);
            
            if (error.message.includes("replacement fee too low")) {
                console.log("💰 Trying with even higher gas fees...");
                
                try {
                    const higherGasTx = await wallet.sendTransaction({
                        to: wallet.address,
                        value: 0,
                        nonce: nonce,
                        maxFeePerGas: ethers.parseUnits("200", "gwei"), // 超高 gas 费
                        maxPriorityFeePerGas: ethers.parseUnits("50", "gwei"),
                        gasLimit: 21000
                    });
                    
                    console.log(`💥 Ultra-high gas tx sent: ${higherGasTx.hash}`);
                } catch (secondError: any) {
                    console.log(`💀 Ultra-high gas also failed:`, secondError.message);
                }
            }
        }
        
        await new Promise(resolve => setTimeout(resolve, 3000));
    }
    
    console.log("\n📊 All replacement transactions sent!");
    console.log("⏰ Waiting 3 minutes for network to process...");
    
    await new Promise(resolve => setTimeout(resolve, 180000));
    
    console.log("🔍 Checking final status...");
    const finalLatest = await provider.getTransactionCount(wallet.address, "latest");
    const finalPending = await provider.getTransactionCount(wallet.address, "pending");
    
    console.log("\n=== Final Results ===");
    console.log("Final latest nonce:", finalLatest, `(0x${finalLatest.toString(16)})`);
    console.log("Final pending nonce:", finalPending, `(0x${finalPending.toString(16)})`);
    console.log("Remaining stuck transactions:", finalPending - finalLatest);
    
    if (finalPending === finalLatest) {
        console.log("🎉 SUCCESS! All stuck transactions cleared!");
        console.log("🚀 You can now proceed with your deployment");
    } else {
        console.log("⚠️ Some transactions may still be pending");
        console.log("💡 Consider waiting longer or using even higher gas fees");
        
        const stillStuck = finalPending - finalLatest;
        console.log(`📋 Nonces ${finalLatest} to ${finalPending - 1} (${stillStuck} total) are still stuck`);
    }
}

directRPCClear()
    .then(() => {
        console.log("\n✅ Script completed");
        process.exit(0);
    })
    .catch(error => {
        console.error("\n❌ Script failed:", error);
        process.exit(1);
    });