// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import {SafeCast} from "./SafeCast.sol";

interface IoldxCONE {
    struct vestPosition {
        uint256 totalVested;
        uint64 lastInteractionTime;
        uint32 VestPeriod;
    }

    function userInfo(
        address account,
        uint256 id
    ) external returns (vestPosition memory);
}

interface token is IERC20 {
    function mint(address recipient, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;
}

contract xCONE is ERC20("xCONE", "xCONE"), Ownable, ReentrancyGuard {
    token public immutable CONE;
    IoldxCONE public immutable oldxCONE =
        IoldxCONE(0xAdeD4A1c5A6be96156876Ed973c2093c08FFB6fF);
    mapping(address => bool) public isMigrated;

    constructor(token _token, uint256 _amount) {
        CONE = _token;
        _mint(msg.sender, _amount);
    }

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct vestPosition {
        uint256 totalVested;
        uint64 lastInteractionTime;
        uint32 VestPeriod;
    }

    event MigratedUser(address indexed user, uint256 length);

    mapping(address => vestPosition[]) public userInfo;
    mapping(address => uint256) public userPositions;

    uint32 public constant vestingPeriod = 200 days;
    uint32 public constant shortVestingPeriod = 20 days;

    function mint(address recipient, uint256 _amount) external onlyOwner {
        _mint(recipient, _amount);
    }

    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }

    function remainTime(
        address _address,
        uint256 id
    ) public view returns (uint256) {
        vestPosition memory position = userInfo[_address][id];
        uint256 timePass = block.timestamp.sub(position.lastInteractionTime);
        uint256 remain;
        if (timePass >= position.VestPeriod) {
            remain = 0;
        } else {
            remain = position.VestPeriod - timePass;
        }
        return remain;
    }

    function vest(uint256 _amount) external nonReentrant {
        require(this.balanceOf(msg.sender) >= _amount, "xCONE balance too low");

        userInfo[msg.sender].push(
            vestPosition({
                totalVested: _amount,
                lastInteractionTime: SafeCast.toUint64(block.timestamp),
                VestPeriod: vestingPeriod
            })
        );
        userPositions[msg.sender] += 1;
        _burn(msg.sender, _amount);
    }

    function vestHalf(uint256 _amount) external nonReentrant {
        require(this.balanceOf(msg.sender) >= _amount, "xCONE balance too low");

        userInfo[msg.sender].push(
            vestPosition({
                totalVested: _amount.mul(100).div(200),
                lastInteractionTime: SafeCast.toUint64(block.timestamp),
                VestPeriod: shortVestingPeriod
            })
        );
        userPositions[msg.sender] += 1;
        _burn(msg.sender, _amount);
    }

    function lock(uint256 _amount) external nonReentrant {
        require(CONE.balanceOf(msg.sender) >= _amount, "CONE balance too low");
        uint256 amountOut = _amount;
        _mint(msg.sender, amountOut);
        CONE.burn(msg.sender, _amount);
    }

    function claim(uint256 id) external nonReentrant {
        require(remainTime(msg.sender, id) == 0, "vesting not end");
        vestPosition storage position = userInfo[msg.sender][id];
        uint256 claimAmount = position.totalVested;
        position.totalVested = 0;
        CONE.mint(msg.sender, claimAmount);
    }

    function migrateVest() external nonReentrant {
        require(!isMigrated[msg.sender], "Already migrated");
        isMigrated[msg.sender] = true;
        uint8 numberOfPositions;
        for (uint8 i = 0; i < 20; i++) {
            try oldxCONE.userInfo(address(msg.sender), i) returns (
                IoldxCONE.vestPosition memory position
            ) {
                userInfo[msg.sender].push(
                    vestPosition({
                        totalVested: position.totalVested,
                        lastInteractionTime: position.lastInteractionTime,
                        VestPeriod: position.VestPeriod
                    })
                );
                userPositions[msg.sender] += 1;
            } catch {
                numberOfPositions = i;
                break;
            }
        }
        emit MigratedUser(msg.sender, numberOfPositions);
    }
}

