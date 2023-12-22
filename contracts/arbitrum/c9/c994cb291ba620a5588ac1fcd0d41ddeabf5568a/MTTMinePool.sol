// SPDX-License-Identifier: MIT
// Metaline Contracts (Expedition.sol)

pragma solidity >=0.8.0 <=0.9.0;

import "./AccessControl.sol";
import "./Context.sol";

import "./MTT.sol";

import "./TransferHelper.sol";

contract MTTMinePool is
    Context,
    AccessControl
{
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    event MTTMinePoolSend(address indexed userAddr, address indexed caller, uint256 value, bytes reason);

    uint256 public immutable MTT_PER_BLOCK; 

    MTT public MTTContract;

    uint256 public MTT_TOTAL_OUTPUT;

    uint256 public MTT_LIQUIDITY;
    uint256 public MTT_LAST_OUTPUT_BLOCK;

    constructor(
        address _MTTAddr,
        uint256 _perblock
    ) {
        require(_perblock > 0, "MTTMinePool: mtt per block must >0");

        MTTContract = MTT(_MTTAddr);

        MTT_PER_BLOCK = _perblock;
        MTT_LAST_OUTPUT_BLOCK = block.number;
        
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MANAGER_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
    }

    function _output() internal {
        if(MTT_LAST_OUTPUT_BLOCK >= block.number){
            return;
        }

        uint256 output = (block.number - MTT_LAST_OUTPUT_BLOCK) * MTT_PER_BLOCK;
        MTT_LAST_OUTPUT_BLOCK = block.number;
        MTT_LIQUIDITY += output;
        MTT_TOTAL_OUTPUT += output;
    }

    function send(address userAddr, uint256 value, bytes memory reason) external {
        require(hasRole(MINTER_ROLE, _msgSender()), "MTTMinePool: must have minter role");

        _output();

        require(MTT_LIQUIDITY >= value, "MTTMinePool: short of liquidity");
        require(MTTContract.balanceOf(address(this)) >= value, "MTTMinePool: insufficient MTT");

        MTT_LIQUIDITY -= value;
        TransferHelper.safeTransfer(address(MTTContract), userAddr, value);

        emit MTTMinePoolSend(userAddr, _msgSender(), value, reason);
    }
}
