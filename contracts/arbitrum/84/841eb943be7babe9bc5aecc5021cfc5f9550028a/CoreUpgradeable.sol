// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ICore.sol";

abstract contract CoreUpgradeable is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    OwnableUpgradeable,
    ICore
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /*==================================================== Events ====================================================*/

    event Payout(address to, uint256 amount, bool success);
    event PayoutERC20(
        address tokenAddress,
        address to,
        uint256 amount,
        bool success
    );
    event Credited(address from, uint256 amount);
    event CreditedERC20(address tokenAddress, address from, uint256 amount);

    /*==================================================== State Variables ====================================================*/

    bool isWithdrawAvaialable;
    bool isWithdrawERC20Avaialable;

    /*==================================================== Modifiers ====================================================*/

    modifier canWithdraw() {
        require(isWithdrawAvaialable, "Core: withdraw blocked");
        _;
    }

    modifier canWithdrawERC20() {
        require(isWithdrawERC20Avaialable, "Core: withdrawERC20 blocked");
        _;
    }

    modifier onlyGovernance() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "CORE: Not governance"
        );
        _;
    }

    /*==================================================== Functions ===========================================================*/

    /** @dev Creates a contract.
     */
    function __Core_init() public payable onlyInitializing {
        __Ownable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        isWithdrawAvaialable = true;
        isWithdrawERC20Avaialable = true;
    }

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /** @dev withdraws native currency from contract.
     * @param _amount in gwei
     */
    function withdraw(uint256 _amount) external override onlyGovernance canWithdraw {
        uint256 balance = address(this).balance;

        require(_amount <= balance, "amount should be less than balance");

        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed.");

        emit Payout(_msgSender(), _amount, true);
    }

    /** @dev withdraws erc20 currency from contract.
     * @param _tokenAddress *
     * @param _amount *
     */
    function withdrawERC20(
        address _tokenAddress,
        uint256 _amount
    ) external override onlyGovernance canWithdrawERC20 {
        IERC20Upgradeable _token = IERC20Upgradeable(_tokenAddress);
        _token.safeTransfer(_msgSender(), _amount);
        emit PayoutERC20(_tokenAddress, _msgSender(), _amount, true);
    }

    /*==================================================== Internal Functions ===========================================================*/

    /** @dev checks if address is contract
     * @param _address *
     */
    function _isContract(address _address) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }

    /** @dev allows to receive native currency
     */
    receive() external payable {
        emit Credited(_msgSender(), msg.value);
    }
}

