// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {ERC20Burnable} from "./ERC20Burnable.sol";
import {Ownable2Step} from "./Ownable2Step.sol";
import {ERC20} from "./ERC20.sol";

/**
 * @title PreLevelToken
 * @author LevelFinance
 * @notice PreLevelToken is intermediate token issues by protocol in place of usage incentive. User collect their preLVL to convert to LVL token in following ways:
 * - instant convert: with 30% fee in form of USDT. These amount of USDT will be sent to DAO and liquidity pool
 * - vesting: gradually convert preLVL to LVL in 1 year. After start vesting, user can claim their converted LVL or stop vesting at any time. The only requirement is they MUST
 * lock an amount of LVL to staking contract.
 */
contract PreLevelToken is Ownable2Step, ERC20Burnable {
    uint256 public constant MAX_ALLOWED_CAP = 200_000 ether;

    // @notice allowed minter, can added by owner only
    mapping(address minter => bool enable) public isMinter;
    // @notice all allowed minter
    address[] public allMinters;
    // @notice amount of which each minter can mint, controlled by controller or owner
    mapping(address minter => uint256 cap) public minterCap;
    /// @notice party allowed to set cap for each minter
    address public controller;

    constructor() Ownable2Step() ERC20("Pre Level Token", "preLVL") {}

    function getAllMinters() external view returns (address[] memory) {
        return allMinters;
    }

    function mint(address _account, uint256 _amount) external {
        address minter = msg.sender;
        uint256 available = minterCap[minter];
        if (available < _amount) revert MinterNotAllowed();

        unchecked {
            // never overflow, checked above
            minterCap[minter] -= _amount;
        }
        _mint(_account, _amount);
    }

    function addMinter(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddress();
        if (!isMinter[_address]) {
            isMinter[_address] = true;
            allMinters.push(_address);
            emit MinterAdded(_address);
        }
    }

    function removeMinter(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddress();

        if (isMinter[_address]) {
            isMinter[_address] = false;
            uint256 nMinter = allMinters.length;
            for (uint256 i = 0; i < nMinter; i++) {
                if (_address == allMinters[i]) {
                    allMinters[i] = allMinters[nMinter - 1];
                    break;
                }
            }
            allMinters.pop();
            emit MinterRemoved(_address);
        }
    }

    function setMinterCap(address _minter, uint256 _allowedAmount) external {
        if (msg.sender != controller && msg.sender != owner()) revert Unauthorized();
        if (_minter == address(0)) revert ZeroAddress();
        if (!isMinter[_minter]) revert MinterNotAllowed();
        if (_allowedAmount > MAX_ALLOWED_CAP) revert MaxCapTooHigh();

        minterCap[_minter] = _allowedAmount;
        emit MinterSet(_minter, _allowedAmount);
    }

    function setController(address _controller) external onlyOwner {
        if (_controller == address(0)) revert ZeroAddress();
        if (controller != _controller) {
            controller = _controller;
            emit ControllerSet(_controller);
        }
    }

    // ======== ERRORS ========
    error Unauthorized();
    error MinterNotAllowed();
    error ZeroAddress();
    error MaxCapTooHigh();

    // ======== EVENTS ========
    event MinterSet(address minter, uint256 allowedAmount);
    event MinterAdded(address minter);
    event MinterRemoved(address minter);
    event ControllerSet(address controller);
}

