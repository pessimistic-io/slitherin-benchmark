// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "./Create2.sol";
import "./Ownable.sol";
import { IEntryPoint } from "./IEntryPoint.sol";
import "./TokenPocketAAProxy.sol";

contract TokenPocketAAFactory is Ownable {

    address public accountImplementation;
    
    event Upgraded(address indexed implementation, address indexed newImplementation);
    event CreateAccount(address indexed account, address indexed owner, address implementation, uint256 salt);

    constructor(address _accountImplementation) Ownable() {
        accountImplementation = _accountImplementation;
    }

    function upgradeImplementation(address newImplementation) external onlyOwner {
        emit Upgraded(accountImplementation, newImplementation);
        accountImplementation = newImplementation;
    }

    function addStake(IEntryPoint entryPoint, uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value : msg.value}(unstakeDelaySec);
    }

    function unlockStake(IEntryPoint entryPoint) external onlyOwner {
        entryPoint.unlockStake();
    }

    function withdrawStake(IEntryPoint entryPoint, address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
    }

    function createAccount(address owner,uint256 salt) public returns (address ret) {
        address addr = getAddress(owner, salt);
        uint codeSize = addr.code.length;
        if (codeSize > 0) {
            return (payable(addr));
        }
        ret = payable(new TokenPocketAAProxy{salt : bytes32(salt)}(
                accountImplementation,
                getInitializeData(owner)
            ));
        emit CreateAccount(address(ret), owner, accountImplementation, salt);
    }

    function getAddress(address owner,uint256 salt) public view returns (address) {
        
        return Create2.computeAddress(bytes32(salt), keccak256(abi.encodePacked(
                type(TokenPocketAAProxy).creationCode,
                abi.encode(
                    address(accountImplementation),
                    getInitializeData(owner)
                )
            )));
    }

    function getInitializeData(address owner) internal pure returns (bytes memory) {
        bytes4 sig = bytes4(keccak256("initialize(address)"));
        bytes memory data = abi.encodeWithSelector(sig, owner);
        return data;
    }
}
