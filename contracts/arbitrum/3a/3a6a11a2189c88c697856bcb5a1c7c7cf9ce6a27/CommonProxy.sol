//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./console.sol";
import "./ICommonProxy.sol";
import "./MultiSigConfigurable.sol";
import "./console.sol";

/**
 * All proxies extend this base proxy class that handles the delegate call
 * functionality to the underlying logic. It extends the multi-sig configuration
 * contract to take advantage of multi-sig upgrade requirements.
 */

contract CommonProxy is MultiSigConfigurable, ICommonProxy {

    string public proxyName;
    
    /**
     * Construct proxy with a unique name, underlying impl address, and calldata
     * to initialize the underlying implementation
     */
    constructor(string memory _proxyName, address _impl, bytes memory initData) {
        proxyName = _proxyName;
        if(initData.length > 0) {
            (bool s, bytes memory d) = _impl.delegatecall(initData);
            if(!s) {
                console.log("FAILED TO INITIALIZE");
                console.logBytes(d);
                revert("Failed to initialize implementation");
            }
        }
    }

    /**
     * Get the address of the underlying contract address
     */
    function logic() public view returns (address) {
        return LibStorage.getMultiSigStorage().logic;
    }

    //call impl using proxy's state data
    fallback() external {
        //get the logic from storage
        address addr = LibStorage.getMultiSigStorage().logic;
        assembly {
            //and call it
            calldatacopy(0x0, 0x0, calldatasize())
            let success := delegatecall(sub(gas(), 10000), addr, 0x0, calldatasize(), 0, 0)
            let retSz := returndatasize()
            returndatacopy(0, 0, retSz)
            switch success
                case 0 {
                    revert(0, retSz)
                }
                default {
                    return(0, retSz)
                }
        }
    }
}
