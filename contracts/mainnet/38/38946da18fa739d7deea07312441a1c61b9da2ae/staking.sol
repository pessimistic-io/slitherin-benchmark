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
 * @title Flipping Club Staking Contract v5 - flippingclub.xyz
 */

pragma solidity 0.8.17;

import "./IERC721Receiver.sol";
import "./Context.sol";
import "./Pausable.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./stakeable.sol";

contract FlippingClubContract is Stakeable, Pausable, Ownable {
    using SafeMath for uint256;
    address payable treasury;
    bytes32 private constant ADMIN = keccak256(abi.encodePacked("ADMIN"));
    bytes32 private constant EXEC = keccak256(abi.encodePacked("EXEC"));
    uint256 AllowanceKeyVal = 500000000000000000;
    event Minted__Stake(address indexed user, uint256 quantity);
    event Minted__Allowance(address indexed user, uint256 quantity);

    constructor(address payable _treasury) {
        treasury = _treasury;
        _grantRole(ADMIN, _treasury);
        _grantRole(EXEC, _treasury);
        _grantRole(ADMIN, msg.sender);
        _grantRole(EXEC, msg.sender);
    }

    receive() external payable {
        payable(treasury).transfer(address(this).balance);
    }

    function stake(
        uint256 pamount,
        uint256 kmount,
        uint256 startDate,
        uint256 endDate,
        uint256 percentage,
        string calldata uniqueID,
        bytes32 hash
    ) external payable nonReentrant whenNotPaused {
        uint256 amount = pamount.add(kmount);
        if (msg.value > 0) {
            payable(treasury).transfer(msg.value);
        }
        require(
            hash ==
                keccak256(
                    abi.encodePacked(uniqueID, percentage, startDate, endDate)
                ),
            "Not Authorized."
        );
        _stake(amount, startDate, endDate, percentage, uniqueID, msg.sender);
    }

    function stake__exec(
        uint256 amount,
        uint256 startDate,
        uint256 endDate,
        uint256 percentage,
        string calldata uniqueID,
        address spender
    ) external nonReentrant whenNotPaused onlyRole(EXEC) {
        _stake(amount, startDate, endDate, percentage, uniqueID, spender);
    }

    function stake__withdraw(string calldata uniqueID)
        external
        nonReentrant
        whenNotPaused
    {
        _withdraw(uniqueID, msg.sender);
    }

    function stake__close(string calldata uniqueID)
        external
        nonReentrant
        whenNotPaused
        onlyRole(EXEC)
    {
        _close(uniqueID);
    }

    function init() external nonReentrant onlyRole(ADMIN) {
        payable(msg.sender).transfer(address(this).balance);
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function pause() external whenNotPaused onlyRole(ADMIN) {
        _pause();
    }

    function unPause() external whenPaused onlyRole(ADMIN) {
        _unpause();
    }

    function mint__stake(uint256 quantity, bytes32 stakeAuth) external payable {
        require(
            stakeAuth == keccak256(abi.encodePacked(quantity, msg.value)),
            "Invalid Request"
        );
        require(msg.value > 0, "Invalid Amount");
        payable(treasury).transfer(msg.value);
        emit Minted__Stake(msg.sender, quantity);
    }

    function mint__allowance(uint256 quantity, bytes32 AllowanceSerial)
        external
        payable
    {
        require(
            AllowanceSerial == keccak256(abi.encodePacked(quantity, msg.value)),
            "Invalid Request"
        );
        require(msg.value == quantity.mul(AllowanceKeyVal), "Invalid Amount");
        payable(treasury).transfer(msg.value);
        emit Minted__Allowance(msg.sender, quantity);
    }

    function changeAllowanceKeyVal(uint256 newValue) external onlyRole(ADMIN) {
        AllowanceKeyVal = newValue;
    }

    function getHash(
        string calldata uniqueID,
        uint256 percentage,
        uint256 startDate,
        uint256 endDate
    ) public view onlyRole(ADMIN) returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(uniqueID, percentage, startDate, endDate)
            );
    }
}

