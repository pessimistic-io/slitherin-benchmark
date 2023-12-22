// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

// Persistence alone is omnipotent!

// https://protoverse.ai/ 

// ProtoVerse offers secure, no-code Web3 mass-adoption tools.
// Self-Custody; your private keys, your smart contracts!

//  __   __   __  ___  __        ___  __   __   ___      __        __
// |__) |__) /  \  |  /  \ \  / |__  |__) /__` |__      |__) \  / |__)
// |    |  \ \__/  |  \__/  \/  |___ |  \ .__/ |___     |     \/  |  \

// $PVR is audited by the renowned Binance Labs incubated company, Salus Security https://salusec.io/!

/*                                                                                                                  
                                            ██████████                                  
                                      ░░  ██░░░░░░░░░░██                                
                                        ██░░░░░░░░░░░░░░██                              
                                        ██░░░░░░░░████░░██████████                      
                            ██          ██░░░░░░░░████░░██▒▒▒▒▒▒██                      
                          ██░░██        ██░░░░░░░░░░░░░░██▒▒▒▒▒▒██                      
                          ██░░░░██      ██░░░░░░░░░░░░░░████████                        
                        ██░░░░░░░░██      ██░░░░░░░░░░░░██                              
                        ██░░░░░░░░████████████░░░░░░░░██                                
                        ██░░░░░░░░██░░░░░░░░░░░░░░░░░░░░██                              
                        ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██                            
                        ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██                            
                        ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██                            
                        ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██                            
                        ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██                            
                        ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██                              
                          ██░░░░░░░░░░░░░░░░░░░░░░░░░░██                                
                            ██████░░░░░░░░░░░░░░░░████                                  
                                  ████████████████                                      
                                                            
 */
import "./TransparentUpgradeableProxy.sol";
import "./ProxyAdmin.sol";
import "./TemporaryImplementation.sol";
import "./Auth.sol";

contract ProxyDeployer is Auth {
    address public proxyAddress;
    address public adminAddress;
    address public implementationV1;

    constructor() Auth(msg.sender) {
        // Deploy ImplementationV1
        implementationV1 = address(new TemporaryImplementation());

        // Deploy ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        adminAddress = address(proxyAdmin);

        // Data for initializing the implementation contract
        bytes memory initData = abi.encodeWithSignature("initialize()");

        // Deploy TransparentUpgradeableProxy with initialization
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            implementationV1,
            adminAddress,
            initData
        );
        proxyAddress = address(proxy);
    }

    function transferProxyAdminOwnership(address newOwner) external onlyOwner {
        ProxyAdmin(adminAddress).transferOwnership(newOwner);
    }
}
