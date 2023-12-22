// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;
pragma abicoder v2;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./AddressUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract ClaimProxy is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Beneficiary {
        address recipient;
        uint256 amount;
    }

    IERC20Upgradeable public token;
    address public target;
    bytes public callData;

    uint256 public totalAmount;
    uint256 public beneficiaryCount;
    Beneficiary[] public beneficiaries;

    event Claim(address indexed token, address indexed target, bytes callData);
    event Disperse(address indexed token, uint256 balance);

    function initialize(
        address token_,
        address target_,
        bytes memory callData_
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        _setClaimContext(token_, target_, callData_);
    }

    function listBeneficiaries() public view returns (Beneficiary[] memory) {
        Beneficiary[] memory result = new Beneficiary[](beneficiaryCount);
        for (uint256 i = 0; i < beneficiaryCount; i++) {
            result[i] = beneficiaries[i];
        }
        return result;
    }

    /// @notice Set all the beneficiaries. User should always pass the full list.
    ///         RewardClaimContract ==reward==> ClaimProxy ==reward==> Beneficiaries.
    ///         There should left no funds in the claimProxy except for the loss from accuracy,
    ///         which will be delivered at next claim.
    function setBeneficiaries(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(recipients.length == amounts.length, "UnmatchedInputs");
        uint256 size = recipients.length;
        uint256 cap = beneficiaries.length;
        uint256 total = 0;
        for (uint256 i = 0; i < size; i++) {
            Beneficiary memory beneficiary = Beneficiary({
                recipient: recipients[i],
                amount: amounts[i]
            });
            if (i < cap) {
                beneficiaries[i] = beneficiary;
            } else {
                beneficiaries.push(beneficiary);
            }
            total = total + amounts[i];
        }
        totalAmount = total;
        beneficiaryCount = size;
    }

    /// @notice Set the context to claim from external contract.
    function setClaimContext(
        address token_,
        address target_,
        bytes memory callData_
    ) external onlyOwner {
        _setClaimContext(token_, target_, callData_);
    }

    /// @notice Do call and forward claimed tokens to beneficiaries.
    function claim() external nonReentrant {
        require(beneficiaryCount > 0, "NoBeneficiaries");
        _claim();
        _disperse();
    }

    /// @notice Disperse balance within contract.
    function disperse() external nonReentrant {
        require(beneficiaryCount > 0, "NoBeneficiaries");
        _disperse();
    }

    function _setClaimContext(
        address token_,
        address target_,
        bytes memory callData_
    ) internal {
        require(token_.isContract(), "NonContractToken");
        require(target_.isContract(), "NonContractTarget");

        token = IERC20Upgradeable(token_);
        target = target_;
        callData = callData_;
    }

    function _claim() internal {
        require(target != address(0), "EmptyTarget");
        target.functionCall(callData);
        emit Claim(address(token), target, callData);
    }

    function _disperse() internal {
        require(address(token) != address(0), "EmptyToken");
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) {
            return;
        }
        for (uint256 i = 0; i < beneficiaryCount; i++) {
            Beneficiary storage beneficiary = beneficiaries[i];
            uint256 amount = (balance * beneficiary.amount) / totalAmount;
            token.safeTransfer(beneficiary.recipient, amount);
        }
        emit Disperse(address(token), balance);
    }
}

