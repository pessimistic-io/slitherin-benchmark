// SPDX-License-Identifier: MIT
// Copyright (c) 2023 Flipping Club - flippingclub.xyz
/**
 *  ______ _ _             _                _____ _       _
 * |  ____| (_)           (_)              / ____| |     | |
 * | |__  | |_ _ __  _ __  _ _ __   __ _  | |    | |_   _| |__
 * |  __| | | | '_ \| '_ \| | '_ \ / _` | | |    | | | | | '_ \
 * | |    | | | |_) | |_) | | | | | (_| | | |____| | |_| | |_) |
 * |_|    |_|_| .__/| .__/|_|_| |_|\__, |  \_____|_|\__,_|_.__/
 *            | |   | |             __/ |
 *            |_|   |_|            |___/
 *
 * @title Flipping Club Staking Contract - Dependency v4.1.1 - flippingclub.xyz
 * @author Flipping Club Team - (Team B)
 */

pragma solidity 0.8.17;

import "./SafeMath.sol";
import "./ReentrancyGuard.sol";

contract Stakeable is ReentrancyGuard {
    using SafeMath for uint256;
    bytes32 private constant ADMIN = keccak256(abi.encodePacked("ADMIN"));
    bytes32 private constant EXEC = keccak256(abi.encodePacked("EXEC"));
    
    mapping(bytes32 => mapping(address => bool)) public roles;
    event GrantRole(bytes32 indexed role, address indexed account);
    event RevokeRole(bytes32 indexed role, address indexed account);
    event Staked(
        address indexed user,
        uint256 amount,
        uint256 startDate,
        uint256 endDate,
        uint256 percentage,
        string uniqueID
    );
    event Withdrawn(address indexed user, string uniqueID);
    struct Stake {
        address user;
        uint256 amount;
        uint256 startDate;
        uint256 endDate;
        uint256 percentage;
        string uniqueID;
    }
    mapping(string => Stake[]) private Stakes;

    constructor() {}

    function _stake(
        uint256 amount,
        uint256 startDate,
        uint256 endDate,
        uint256 percentage,
        string calldata uniqueID,
        address _Sender
    ) internal {
        require(Stakes[uniqueID].length <= 0, "Duplicate ID");
        Stakes[uniqueID].push(
            Stake(
                _Sender,
                amount,
                startDate,
                endDate,
                percentage,
                uniqueID
            )
        );
        emit Staked(_Sender, amount, startDate, endDate, percentage, uniqueID);
    }

    function _withdraw(string calldata uniqueID, address _spender) internal {
        require(Stakes[uniqueID].length > 0, "No Position.");
        require(Stakes[uniqueID][0].user == _spender, "Not Authorized.");
        require(Stakes[uniqueID][0].endDate <= block.timestamp, "Not Ready.");
        delete Stakes[uniqueID];
        emit Withdrawn(_spender, uniqueID);
    }

    function _close(string calldata uniqueID) internal {
        require(Stakes[uniqueID].length > 0, "No Position.");
        delete Stakes[uniqueID];
    }

    function getStake__byUID(string calldata uniqueID)
        external
        view
        returns (Stake memory)
    {
        require(Stakes[uniqueID].length > 0, "No Position.");
        Stake memory summary = Stakes[uniqueID][0];

        return summary;
    }


    function _onlyRole(bytes32 _role) public view {
        require(roles[_role][msg.sender], "Not authorized.");
    }

    modifier onlyRole(bytes32 _role) {
        _onlyRole(_role);
        _;
    }

    function _grantRole(bytes32 _role, address _account) internal {
        roles[_role][_account] = true;
        emit GrantRole(_role, _account);
    }

    function grantRole(bytes32 _role, address _account)
        external
        onlyRole(ADMIN)
    {
        _grantRole(_role, _account);
    }

    function _revokeRole(bytes32 _role, address _account) internal {
        roles[_role][_account] = false;
        emit RevokeRole(_role, _account);
    }

    function revokeRole(bytes32 _role, address _account)
        external
        onlyRole(ADMIN)
    {
        _revokeRole(_role, _account);
    }
}

