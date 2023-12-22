// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./ICrucibleToken.sol";
import "./ICrucibleTokenDeployer.sol";
import "./ICrucibleFactory.sol";
import "./IHasTaxDistributor.sol";
import "./IGeneralTaxDistributor.sol";
import "./ERC20.sol";
import "./FullMath.sol";
import "./TokenReceivable.sol";

contract CrucibleToken is ERC20, TokenReceivable, ICrucibleToken {
    uint256 constant MAX_FEE_X10k = 0.6 * 10000;

    struct FeeOverride {
        OverrideState over;
        uint64 feeX10000;
    }

    address public immutable factory;
    address public router;
    address public override baseToken; // Remocing immutables to allow etherscan verification to work. Hopefully etherscan gives us a solution
    uint64 public feeOnTransferX10000;
    uint64 public feeOnWithdrawX10000;
    mapping(address => FeeOverride) public feeOverrides;

    event Withdrawn(uint256 amount, uint256 fee, address from, address to);
    event Deposited(address token, uint256 amount, address to);
    event FeeSet(address target, OverrideState overrideType, uint64 feeX10k);
    event FeesUpdated(uint64 feeOnTransferX10000, uint64 feeOnWithdrawX10000);

    modifier onlyRouter() {
        require(msg.sender == router, "CT: not allowed");
        _;
    }

    constructor() {
        address token;
        address fac;
        (
            fac,
            token,
            feeOnTransferX10000,
            feeOnWithdrawX10000,
            name,
            symbol
        ) = ICrucibleTokenDeployer(msg.sender).parameters();
        decimals = safeDecimals(token);
        baseToken = token;
        router = ICrucibleFactory(fac).router();
        factory = fac;
    }

    /**
     @notice Upgrades a router
     @param _router The new router
     @dev Can only be called by the current router
     */
    function upgradeRouter(address _router
    ) external override onlyRouter {
        require(_router != address(0), "CT: router required");
        router = _router;
    }

    /**
     @notice Allow overriding the global crucible fees. Only router action
     @param newFeeOnTransferX10000 Fee on transfer
     @param newFeeOnWithdrawX10000 Fee on withdraw
     */
    function updateCrucibleFees(
        uint64 newFeeOnTransferX10000,
        uint64 newFeeOnWithdrawX10000
    ) external override onlyRouter {
        require(newFeeOnTransferX10000 < MAX_FEE_X10k, "CT: fee too large");
        require(newFeeOnWithdrawX10000 < MAX_FEE_X10k, "CT: fee too large");
        require(newFeeOnTransferX10000 != 0 && newFeeOnWithdrawX10000 != 0, "CT: one fee required");
        feeOnTransferX10000 = newFeeOnTransferX10000;
        feeOnWithdrawX10000 = newFeeOnWithdrawX10000;
        emit FeesUpdated(feeOnTransferX10000, feeOnWithdrawX10000);
    }

    /**
     @notice Overrides fee for a target
     @param target The target to be overriden
     @param overrideType The type of override
     @param newFeeX10000 The new fee
     @dev Can only be called by the router
     */
    function overrideFee(
        address target,
        OverrideState overrideType,
        uint64 newFeeX10000
    ) external override onlyRouter {
        require(newFeeX10000 < MAX_FEE_X10k, "CT: fee too large");
        feeOverrides[target] = FeeOverride({
            over: overrideType,
            feeX10000: newFeeX10000
        });
        emit FeeSet(target, overrideType, newFeeX10000);
    }

    /**
     @notice Deposits into the crucible
        Can only be called by the router
     @param to Receiver of minted tokens
     @return amount The deposited amount
     */
    function deposit(address to
    ) external override onlyRouter returns (uint256 amount) {
        amount = sync(baseToken);
        require(amount != 0, "CT: empty");
        _mint(to, amount);
        emit Deposited(baseToken, amount, to);
    }

    /**
     @notice Withdraws from the crucible
     @param to Receiver of minted tokens
     @param amount The amount to withdraw
     @return fee The fee
     @return withdrawn The withdrawn amounts
     */
    function withdraw(address to, uint256 amount
    ) external override returns (uint256 fee, uint256 withdrawn) {
        (fee, withdrawn) = _withdraw(msg.sender, to, amount);
    }

    /*
     @notice Burn the underlying asset. If not burnable, send to the factory.
     @param amount Amount to burn
     */
    function burn(uint256 amount
    ) external virtual {
        require(amount != 0, "CT: amount required");
        doBurn(msg.sender, amount);
    }

    /*
     @notice Burn the underlying asset. If not burnable, send to the factory.
     @param from The address to burn from
     @param amount Amount to burn
     */
    function burnFrom(address from, uint256 amount
    ) external virtual {
        require(from != address(0), "CT: from required");
        require(amount != 0, "CT: amount required");
        uint256 decreasedAllowance = allowance[from][msg.sender] - amount;

        _approve(from, msg.sender, decreasedAllowance);
        doBurn(from, amount);
    }

    /**
     @notice Withdraws from crucible
     @param from From address
     @param to To address
     @param amount The amount
     @return fee The fee
     @return withdrawn The withdrawn amount
     */
    function _withdraw(
        address from,
        address to,
        uint256 amount
    ) internal virtual returns (uint256 fee, uint256 withdrawn) {
        fee = calculateFeeX10000(amount, feeOnWithdrawX10000);
        withdrawn = amount - fee;
        address td = IHasTaxDistributor(router).taxDistributor();
        tax(from, td, fee);
        _burn(from, withdrawn);
        sendToken(baseToken, to, withdrawn);
        emit Withdrawn(amount, fee, from, to);
    }

    /**
     @notice Burns tokens. Send base tokens to factory to be locke or burned later
     @param from The from address
     @param amount The amount
     */
    function doBurn(address from, uint256 amount
    ) internal {
        sendToken(baseToken, factory, amount);
        _burn(from, amount);
    }

    /**
     @notice Overrides the ERC20 transfer method
     @param sender The sender
     @param recipient The recipient
     @param amount The amount
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        FeeOverride memory overFrom = feeOverrides[sender];
        FeeOverride memory overTo = feeOverrides[recipient];
        address td = IHasTaxDistributor(router).taxDistributor();
        if (sender == td || recipient == td) {
            _doTransfer(sender, recipient, amount);
            return;
        }

        uint256 feeRatioX10k = 0;
        bool overriden = false;
        if (
            overFrom.over == OverrideState.OverrideOut ||
            overFrom.over == OverrideState.OverrideBoth
        ) {
            feeRatioX10k = overFrom.feeX10000;
            overriden = true;
        }
        if (
            (overTo.over == OverrideState.OverrideIn ||
                overTo.over == OverrideState.OverrideBoth) &&
            overTo.feeX10000 >= feeRatioX10k
        ) {
            feeRatioX10k = overTo.feeX10000;
            overriden = true;
        }
        if (feeRatioX10k == 0 && !overriden) {
            feeRatioX10k = feeOnTransferX10000;
        }
        uint256 fee = feeRatioX10k == 0 ? 0 : calculateFeeX10000(amount, feeRatioX10k);
        amount = amount - fee;
        if (fee != 0) {
            tax(sender, td, fee);
        }
        _doTransfer(sender, recipient, amount);
    }

    /**
     @notice Just does the transfer
     @param sender The sender
     @param recipient The recipient
     @param amount The amount
     */
    function _doTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        ERC20._transfer(sender, recipient, amount);
    }

    /**
     @notice charges the tax
     @param from From address
     @param taxDist The tax distributor contract
     @param amount The tax amount
     */
    function tax(
        address from,
        address taxDist,
        uint256 amount
    ) internal {
        _doTransfer(from, taxDist, amount);
        IGeneralTaxDistributor(taxDist).distributeTaxAvoidOrigin(address(this), from);
    }

    /**
     @notice Gets the decimals or default
     @param token The token
     @return The decimals
     */
    function safeDecimals(address token
    ) private view returns (uint8) {
        (bool succ, bytes memory data) = token.staticcall(
            abi.encodeWithSignature(("decimals()"))
        );
        if (succ) {
            return abi.decode(data, (uint8));
        } else {
            return 18;
        }
    }

    /**
     @notice Calculates the fee
     @param amount The amount
     @param feeX10000 The fee rate
     @return The fee amount
     */
    function calculateFeeX10000(uint256 amount, uint256 feeX10000
    ) private pure returns (uint256) {
        return FullMath.mulDiv(amount, feeX10000, 10000);
    }
}

