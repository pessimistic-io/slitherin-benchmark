// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "./TokenPocketAAFactory.sol";
import "./TokenPocketAccount.sol";
import "./Create2.sol";
import "./IEntryPoint.sol";

interface IOwnable {
    function transferOwnership(address newOwner) external;
}

contract AADeployer {

    event Deployed(address deployedAddress, address owner, uint256 salt);

    constructor(){}

    function deployImplementation(IEntryPoint entryPoint, uint256 salt) external {
        address addr = getDeployImplementationAddress(msg.sender, entryPoint, salt);
        uint codeSize = addr.code.length;
        if (codeSize > 0) {
            revert("salt deployed");
        }
        bytes32 deploySalt = keccak256(abi.encodePacked(msg.sender, salt));
        address ret = payable(new TokenPocketAccount{salt : deploySalt}(
                entryPoint
            ));
        require(addr == ret);
        emit Deployed(ret, msg.sender, salt);
    }

    function deployFactory(address accountImplementation, address executor, uint256 salt) external {
        address addr = getDeployFactoryAddress(msg.sender, accountImplementation, salt);
        uint codeSize = addr.code.length;
        if (codeSize > 0) {
            revert("salt deployed");
        }
        bytes32 deploySalt = keccak256(abi.encodePacked(msg.sender, salt));
        address ret = address(new TokenPocketAAFactory{salt : deploySalt}(
                accountImplementation
            ));
        require(addr == ret);
        //transfer owner
        IOwnable(ret).transferOwnership(executor);
        emit Deployed(ret, executor, salt);
    }

    function getDeployImplementationAddress(address deployer, IEntryPoint entryPoint, uint256 salt) public view returns (address ret) {
        bytes32 deploySalt = keccak256(abi.encodePacked(deployer, salt));
        return Create2.computeAddress(deploySalt, keccak256(abi.encodePacked(
                type(TokenPocketAccount).creationCode,
                abi.encode(
                    address(entryPoint)
                )
            )));
    }

    function getDeployFactoryAddress(address deployer, address accountImplementation, uint256 salt) public view returns (address ret) {
        bytes32 deploySalt = keccak256(abi.encodePacked(deployer, salt));
        return Create2.computeAddress(deploySalt, keccak256(abi.encodePacked(
                type(TokenPocketAAFactory).creationCode,
                abi.encode(accountImplementation)
            )));
    }
}
