// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPumpFactoryLite {
    function totalIndex() external view returns (uint256);
    function index(uint256) external view returns (address);
    function creator(address) external view returns (address);
    function createdTime(address) external view returns (uint256);
}

interface IERC20Token {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
}

contract BatchVerifyERC20Tokens is Script {    
    // Constructor arguments for ERC20Token
    uint256 constant INITIAL_TOKEN = 1000000000 ether;
    address public PUMP_FACTORY;
    
    function run(address _pumpFactory) external {
        PUMP_FACTORY = _pumpFactory;
        
        vm.startBroadcast();
        
        IPumpFactoryLite factory = IPumpFactoryLite(PUMP_FACTORY);
        uint256 totalTokens = factory.totalIndex();
        
        console.log("Total tokens created:", totalTokens);
        console.log("Starting batch verification...");
        
        // Loop through all created tokens
        for (uint256 i = 1; i <= totalTokens; i++) {
            address tokenAddress = factory.index(i);
            
            if (tokenAddress == address(0)) {
                console.log("Skipping index %d - no token found", i);
                continue;
            }
            
            try this.verifyToken(tokenAddress) {
                console.log("Successfully verified token %d at address:", i);
                console.log(tokenAddress);
            } catch Error(string memory reason) {
                console.log("Failed to verify token %d at address:", i);
                console.log(tokenAddress);
                console.log("Reason:", reason);
            } catch {
                console.log("Failed to verify token %d at address:", i);
                console.log(tokenAddress);
                console.log("Unknown error occurred");
            }
            
            // Add a small delay to avoid rate limiting
            vm.sleep(1000); // 1 second delay
        }
        
        vm.stopBroadcast();
        console.log("Batch verification completed!");
    }
    
    function verifyToken(address tokenAddress) external {
        IERC20Token token = IERC20Token(tokenAddress);
        
        // Get token details
        string memory name = token.name();
        string memory symbol = token.symbol();
        uint256 totalSupply = token.totalSupply();
        
        console.log("Verifying token:", name);
        console.log("Symbol:", symbol);
        console.log("Address:");
        console.log(tokenAddress);
        console.log("Total Supply:", totalSupply);
        
        // Execute forge verify command
        string[] memory verifyCmd = new string[](11);
        verifyCmd[0] = "forge";
        verifyCmd[1] = "verify-contract";
        verifyCmd[2] = vm.toString(tokenAddress);
        verifyCmd[3] = "--rpc-url";
        verifyCmd[4] = "https://rpc.bitkubchain.io";
        verifyCmd[5] = "--verifier";
        verifyCmd[6] = "blockscout";
        verifyCmd[7] = "--skip-is-verified-check";
        verifyCmd[8] = "--verifier-url";
        verifyCmd[9] = "https://www.kubscan.com/api/";
        verifyCmd[10] = "src/ERC20Token.sol:ERC20Token";

        bytes memory result = vm.ffi(verifyCmd);
        
        if (result.length > 0) {
            console.log("Verification result:", string(result));
        }
    }
    
    function getSourceCode() internal pure returns (string memory) {
        // You would need to include the actual source code here
        // For brevity, returning a placeholder
        return "// ERC20Token source code would go here";
    }
    
    function getConstructorArgs(string memory name, string memory symbol) internal pure returns (string memory) {
        // Encode constructor arguments
        bytes memory encoded = abi.encode(name, symbol, uint256(INITIAL_TOKEN));
        return vm.toString(encoded);
    }
    
    function getNetworkSuffix() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 1) return ""; // Mainnet
        if (chainId == 96) return "-kub";
        if (chainId == 56) return "-bscscan";
        return ""; // Default to mainnet
    }
    
    // Utility function to get all token addresses at once
    function getAllTokenAddresses() external view returns (address[] memory) {
        IPumpFactoryLite factory = IPumpFactoryLite(PUMP_FACTORY);
        uint256 total = factory.totalIndex();
        address[] memory tokens = new address[](total);
        
        for (uint256 i = 1; i <= total; i++) {
            tokens[i-1] = factory.index(i);
        }
        
        return tokens;
    }
    
    // Function to verify specific range of tokens
    function verifyTokenRange(uint256 startIndex, uint256 endIndex, address _pumpFactory) external {
        PUMP_FACTORY = _pumpFactory;
        
        vm.startBroadcast();
        
        IPumpFactoryLite factory = IPumpFactoryLite(PUMP_FACTORY);
        uint256 totalTokens = factory.totalIndex();
        
        require(startIndex <= endIndex && endIndex <= totalTokens, "Invalid range");
        
        console.log("Verifying tokens from index %d to %d", startIndex, endIndex);
        
        for (uint256 i = startIndex; i <= endIndex; i++) {
            address tokenAddress = factory.index(i);
            
            if (tokenAddress != address(0)) {
                try this.verifyToken(tokenAddress) {
                    console.log("Verified token %d:", i);
                    console.log(tokenAddress);
                } catch {
                    console.log("Failed to verify token %d:", i);
                    console.log(tokenAddress);
                }
                
                vm.sleep(1000); // 1 second delay
            }
        }
        
        vm.stopBroadcast();
    }
}