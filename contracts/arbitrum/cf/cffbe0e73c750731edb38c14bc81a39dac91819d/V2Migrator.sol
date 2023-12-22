// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./IERC20.sol";
import "./IERC1155.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

contract V2Migrator is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    string public __NAME__;

    address public oldLqdr;
    address public newLqdr;
    mapping(address => bool) public whitelistedContract;

    bool public redeemEnded;
    uint256 public totalRedeemed;

    event Redeemed(address sender, uint256 amount);

    constructor() public {}

    function initialize(
        address _oldLqdr,
        address _newLqdr
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __NAME__ = "LqdrV2 Migrator";
        oldLqdr = _oldLqdr;
        newLqdr = _newLqdr;
    }

    modifier onlyWhitelisted() {
        if (tx.origin != msg.sender) {
            require(whitelistedContract[msg.sender], "Not whitelisted");
        }
        _;
    }

    function redeem(uint256 _amount) external nonReentrant onlyWhitelisted {
        require(!redeemEnded, "Redeem period ended");
        require(totalRedeemed < IERC20(oldLqdr).totalSupply(), "Total Supply already redeemed");

        uint256 _oldBalance = IERC20(oldLqdr).balanceOf(msg.sender);
        require(_oldBalance >= _amount, "Not enough lqdrs to burn");

        uint256 _newBalnace = IERC20(newLqdr).balanceOf(address(this));
        require(_newBalnace >= _amount, "Not enough lqdrs to mint");

        IERC20(oldLqdr).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(newLqdr).safeTransfer(msg.sender, _amount);

        totalRedeemed = totalRedeemed.add(_amount);

        emit Redeemed(msg.sender, _amount);
    }

    function end() external onlyOwner {
        require(!redeemEnded, "Redeem period already ended");
        redeemEnded = true;
    }

    function restart() external onlyOwner {
        require(redeemEnded, "Redeem period already started");
        redeemEnded = false;
    }

    // ===== SETTERS =====
    function whitelistContract(address _contract) external onlyOwner {
        whitelistedContract[_contract] = true;
    }

    function blacklistContract(address _contract) external onlyOwner {
        whitelistedContract[_contract] = false;
    }
}
