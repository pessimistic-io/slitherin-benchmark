// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./IERC20.sol";
import "./IVe.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

contract AirDropForArb is ReentrancyGuard{
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    uint256 internal constant LOCK_TIME = 2 * 365 * 86400;

    uint256 public startTime;

    uint256 internal serialNumber;

    mapping(address => bool) public whiteList;
    mapping(address => bool) public userClimed;

    address public owner;

    uint256 internal constant PRECISION = 10**18;

    address public ve;

    constructor(address _ve,uint256 _startTime, IERC20 _token) {
        ve = _ve;
        startTime = _startTime;
        token = _token;
        owner = msg.sender;
    }

    function setStartTime(uint256 _startTime) external  {
        require(owner == msg.sender, "not owner");
        startTime = _startTime;
    }

    function addWhiteList(address[] memory addressList) external {
        require(owner == msg.sender, "not owner");
        for (uint256 i = 0; i < addressList.length; i++) {
            whiteList[addressList[i]] = true;   
        }
    }

   function claim() external nonReentrant {
        require(
            block.timestamp >= startTime ,
            "not start"
        );

        require(
            whiteList[msg.sender] == true,
            "not white list"
        );

        require(userClimed[msg.sender] == false, "has clamied");

        uint256 useramount;
        if (serialNumber < 100) {
            useramount = 70000 * PRECISION;
        } else if (serialNumber < 500) {
            useramount = 20000 * PRECISION;
        } else {
            useramount = 3000 * PRECISION;
        }

        IERC20(token).approve(address(ve), type(uint).max);

        IVe(ve).createLockFor(useramount, LOCK_TIME, msg.sender);
        
        ++serialNumber;
        userClimed[msg.sender] = true;
    }
    

    function finish() external {
        require(owner == msg.sender, "not owner");
        uint256 _balanceOf = token.balanceOf(address(this));

        if(_balanceOf > 0) {
            token.safeTransfer(owner, _balanceOf);   
        }
    }

}

