// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./DataTypes.sol";
import "./RBAC.sol";
import "./console.sol";

contract Registry is RBAC {
    address[] public positions;
    address[] public iBTokens;

    mapping(address => bool) public isAdaptorSetup;

    event PositionAdded(address position, address admin);
    event IBTokenAdded(address token, address admin);
    event PositionRemoved(address position, address admin);
    event IBTokenRemoved(address position, address admin);

    function getPositions() public view returns (address[] memory) {
        return positions;
    }

    function getIBTokens() public view returns (address[] memory) {
        return iBTokens;
    }

    function addPosition(address position) public onlyOwner {
        require(!isAdaptorSetup[position], "Already added");

        positions.push(position);
        isAdaptorSetup[position] = true;

        emit PositionAdded(position, msg.sender);
    }

    function removePosition(uint256 index) public onlyOwner {
        address positionAddress = positions[index];
        isAdaptorSetup[positionAddress] = false;
        for (uint256 i = index; i < positions.length - 1; i++) {
            positions[i] = positions[i + 1];
        }
        positions.pop();

        emit PositionRemoved(positionAddress, msg.sender);
    }

    function addIBToken(address token) public onlyOwner {
        require(!isAdaptorSetup[token], "Already added");

        IERC20(token).balanceOf(address(this));

        iBTokens.push(token);
        isAdaptorSetup[token] = true;

        emit IBTokenAdded(token, msg.sender);
    }

    function removeIBToken(uint256 index) public onlyOwner {
        address positionAddress = positions[index];
        require(
            IERC20(positionAddress).balanceOf(address(this)) == 0,
            "IB token balance should be 0."
        );
        isAdaptorSetup[positionAddress] = false;

        for (uint256 i = index; i < iBTokens.length - 1; i++) {
            iBTokens[i] = iBTokens[i + 1];
        }
        iBTokens.pop();

        emit IBTokenRemoved(positionAddress, msg.sender);
    }
}

