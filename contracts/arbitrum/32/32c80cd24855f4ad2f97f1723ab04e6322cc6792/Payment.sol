// contracts/Payment.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./PausableUpgradeable.sol";

import "./AccessControlEnumerableUpgradeable.sol";
import "./VerifySign.sol";

contract Payment is
    VerifySign,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address public currencyAddress;
    mapping(address => uint256) public nonceMapping;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    event Deposit(address sender, uint256 amount);
    event Withdraw(address receiver, uint256 amount);

    function initialize(address initCurrencyAddr) public initializer {
        currencyAddress = initCurrencyAddr;
        __AccessControlEnumerable_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
    }

    function deposit(uint256 amount) external whenNotPaused {
        require(amount > 0, "Payment: Amount invalid");
        uint256 allowance = IERC20Upgradeable(currencyAddress).allowance(
            _msgSender(),
            address(this)
        );
        require(
            allowance >= amount,
            "Payment: Allowance amount lower than amount"
        );
        IERC20Upgradeable(currencyAddress).safeTransferFrom(
            _msgSender(),
            address(this),
            amount
        );
        emit Deposit(_msgSender(), amount);
    }

    function _withdraw(address to, uint256 amount) internal {
        IERC20Upgradeable(currencyAddress).safeTransfer(to, amount);
        emit Withdraw(to, amount);
    }

    function withdraw(address to, uint256 amount)
        public
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
    {
        _withdraw(to, amount);
    }

    function msgHashClaimWithdraw(
        address receiver,
        uint256 amount,
        uint256 nonce,
        uint256 timeExpires
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    address(this),
                    receiver,
                    amount,
                    nonce,
                    timeExpires
                )
            );
    }

    function getSignerWithdraw(
        address receiver,
        uint256 amount,
        uint256 nonce,
        uint256 timeExpires,
        bytes memory signature
    ) public view returns (address) {
        bytes32 messageHash = msgHashClaimWithdraw(
            receiver,
            amount,
            nonce,
            timeExpires
        );
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        return recoverSigner(ethSignedMessageHash, signature);
    }

    function claimWithdraw(
        uint256 amount,
        uint256 nonce,
        uint256 timeExpires,
        bytes memory signature
    ) public whenNotPaused {
        address receiver = _msgSender();
        require(nonce == nonceMapping[receiver], "Payment: Nonce is invalid");
        require(block.timestamp < timeExpires, "Payment: Signature expired");
        // verify signature is signed by owner of contract
        address signer = getSignerWithdraw(
            _msgSender(),
            amount,
            nonce,
            timeExpires,
            signature
        );
        require(
            hasRole(OPERATOR_ROLE, signer),
            "Payment: failure verify withdraw"
        );
        nonceMapping[receiver] = nonceMapping[receiver] + 1;
        _withdraw(_msgSender(), amount);
    }

    /**
     * @dev Disable the {transfer} functions of contract.
     *
     * Can only be called by the current owner.
     * The contract must not be paused.
     */
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Enable the {transfer} functions of contract.
     *
     * Can only be called by the current owner.
     * The contract must be paused.
     */
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}

