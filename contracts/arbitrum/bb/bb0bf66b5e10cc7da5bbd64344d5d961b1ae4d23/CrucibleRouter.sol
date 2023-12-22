// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./IUniswapV2Router01.sol";
import "./IUniswapV2Factory.sol";
import "./IWETH.sol";
import "./IGeneralTaxDistributor.sol";
import "./ICrucibleToken.sol";
import "./IStakeFor.sol";
import "./ReentrancyGuard.sol";
import "./CrucibleFactory.sol";
import "./HasTaxDistributor.sol";
import "./MultiSigCheckable.sol";
import "./Allocatable.sol";
import "./SafeAmount.sol";

/**
 @notice The Crucible Router
 @author Ferrum Network
 */
contract CrucibleRouter is MultiSigCheckable, HasTaxDistributor, ReentrancyGuard {
    using SafeERC20 for IERC20;
    string public constant NAME = "FERRUM_CRUCIBLE_ROUTER";
    string public constant VERSION = "000.001";

    // Using a struct to reduced number of variable in methods.
    struct Amounts {
        uint256 base;
        uint256 pair;
        bool isWeth;
    }

    mapping(address => uint256) public openCaps;
    mapping(address => uint16) public delegatedGroupIds;
    mapping(address => bool) public allowedAmms;

    modifier amm(address _amm) {
        require(allowedAmms[_amm], "CR: amm not allowed");
        _;
    }

    constructor() EIP712(NAME, VERSION) {}

    receive() external payable {
    }

    /**
     @notice Can upgrade router on a crucible
     @param crucible The crucible 
     @param newRouter The new router
     @dev Only callable by admin for router upgrade in future
     */
    function upgradeRouter(address crucible, address newRouter
    ) external onlyOwner {
        require(crucible != address(0), "CR: crucible required");
        require(newRouter != address(0), "CR: newRouter required");
        ICrucibleToken(crucible).upgradeRouter(newRouter);
    }

    /**
     @notice Removes the amm router
     @param amm The amm router
     */
    function removeAmm(address amm
    ) external onlyOwner {
        delete allowedAmms[amm];
    }

    bytes32 constant ALLOW_AMM = keccak256("AllowAmm(address amm)");
    /**
     @notice Allows an AMM to be used for liquidity.
     @param amm The amm router
     @param salt The signature salt
     @param expiry Signature expiry
     @param expectedGroupId Expected group ID for the signature
     @param multiSignature The multisig encoded signature
     */
    function allowAmm(
        address amm,
        bytes32 salt,
        uint64 expiry,
        uint64 expectedGroupId,
        bytes memory multiSignature
    ) external expiryRange(expiry) governanceGroupId(expectedGroupId) {
        bytes32 message = keccak256(
            abi.encode(ALLOW_AMM, amm, salt, expiry)
        );
        verifyUniqueSalt(
            message,
            salt,
            expectedGroupId,
            multiSignature
        );
        allowedAmms[amm] = true;
    }

    bytes32 constant DELEGATE_GROUP_ID =
        keccak256("DelegateGroupId(address crucible,uint16 delegatedGroupId)");
    /**
     @notice Sets a delageted group ID. Once set this group ID can 
         produce signatures for allocations.
     @param crucible The crucible
     @param delegatedGroupId The delegated group ID
     @param salt The signature salt
     @param expiry Signature expiry
     @param expectedGroupId Expected group ID for the signature
     @param multiSignature The multisig encoded signature
     */
    function delegateGroupId(
        address crucible,
        uint16 delegatedGroupId,
        bytes32 salt,
        uint64 expiry,
        uint64 expectedGroupId,
        bytes memory multiSignature
    ) external expiryRange(expiry) {
        bytes32 message = keccak256(
            abi.encode(DELEGATE_GROUP_ID, crucible, delegatedGroupId, salt, expiry)
        );
        verifyUniqueSalt(
            message,
            salt,
            expectedGid(crucible, expectedGroupId),
            multiSignature
        );
        delegatedGroupIds[crucible] = delegatedGroupId;
    }

    bytes32 constant UPDATE_CRUCIBLE_FEES =
        keccak256("UpdateCrucibleFees(address crucible,uint64 newFeeOnTransferX10000,uint64 newFeeOnWithdrawX10000,bytes32 salt,uint64 expiry)");
    /**
     @notice Sets the open cap for a crucible
     @param crucible The crucible address
     @param newFeeOnTransferX10000 The new fee on transfer
     @param newFeeOnWithdrawX10000 The new fee on withdraw
     @param salt The signature salt
     @param expiry Signature expiry
     @param expectedGroupId Expected group ID for the signature
     @param multiSignature The multisig encoded signature
     */
    function updateCrucibleFees(
        address crucible,
        uint64 newFeeOnTransferX10000,
        uint64 newFeeOnWithdrawX10000,
        bytes32 salt,
        uint64 expiry,
        uint64 expectedGroupId,
        bytes memory multiSignature
    ) external expiryRange(expiry) {
        bytes32 message = keccak256(
            abi.encode(UPDATE_CRUCIBLE_FEES, crucible, newFeeOnTransferX10000, newFeeOnWithdrawX10000, salt, expiry)
        );
        verifyUniqueSalt(
            message,
            salt,
            expectedGid(crucible, expectedGroupId),
            multiSignature
        );
        ICrucibleToken(crucible).updateCrucibleFees(newFeeOnTransferX10000, newFeeOnWithdrawX10000);
    }

    bytes32 constant SET_OPEN_CAP =
        keccak256("SetOpenCap(address crucible,uint256 cap,bytes32 salt,uint64 expiry)");
    /**
     @notice Sets the open cap for a crucible
     @param crucible The crucible address
     @param cap The cap
     @param salt The signature salt
     @param expiry Signature expiry
     @param expectedGroupId Expected group ID for the signature
     @param multiSignature The multisig encoded signature
     */
    function setOpenCap(
        address crucible,
        uint256 cap,
        bytes32 salt,
        uint64 expiry,
        uint64 expectedGroupId,
        bytes memory multiSignature
    ) external expiryRange(expiry) {
        bytes32 message = keccak256(
            abi.encode(SET_OPEN_CAP, crucible, cap, salt, expiry)
        );
        verifyUniqueSalt(
            message,
            salt,
            expectedGid(crucible, expectedGroupId),
            multiSignature
        );
        openCaps[crucible] = cap;
    }

    bytes32 constant DEPOSIT_METHOD =
        keccak256(
            "Deposit(address to,address crucible,uint256 amount,bytes32 salt,uint64 expiry)"
        );
    /**
     @notice Deposits into a crucible
     @param to The receiver of crucible tokens
     @param crucible The crucible address
     @param amount The deposit amount
     @param salt The signature salt
     @param expiry Signature expiry
     @param expectedGroupId Expected group ID for the signature
     @param multiSignature The multisig encoded signature
     @return The amount deposited
     */
    function deposit(
        address to,
        address crucible,
        uint256 amount,
        bytes32 salt,
        uint64 expiry,
        uint64 expectedGroupId,
        bytes memory multiSignature
    ) external expiryRange(expiry) nonReentrant returns (uint256) {
        require(amount != 0, "CR: amount required");
        require(to != address(0), "CR: to required");
        require(crucible != address(0), "CR: crucible required");
        if (multiSignature.length != 0) {
            verifyDepositSignature(
                to,
                crucible,
                amount,
                salt,
                expiry,
                expectedGroupId,
                multiSignature
            );
        } else {
            amount = amountFromOpenCap(crucible, amount);
        }
        address token = ICrucibleToken(crucible).baseToken();
        require(SafeAmount.safeTransferFrom(token, msg.sender, crucible, amount) != 0, "CR: nothing transferred");
        return ICrucibleToken(crucible).deposit(to);
    }

    /**
     @notice Deposit into crucible without allocation
     @param to Address of the receiver of crucible
     @param crucible The crucible token
     @param amount The amount to be deposited
     @return The deposited amount
     */
    function depositOpen(
        address to,
        address crucible,
        uint256 amount
    ) external nonReentrant returns (uint256) {
        require(amount != 0, "CR: amount required");
        require(to != address(0), "CR: to required");
        require(crucible != address(0), "CR: crucible required");
        address token = ICrucibleToken(crucible).baseToken();
        amount = amountFromOpenCap(crucible, amount);
        require(SafeAmount.safeTransferFrom(token, msg.sender, crucible, amount) != 0, "CR: nothing transferred");
        return ICrucibleToken(crucible).deposit(to);
    }

    /**
     @notice Deposit and stake in one transaction
     @param to Address of the reciever of stake
     @param crucible The crucible address
     @param amount The amount to be deposited
     @param stake The staking contract address
     @param salt The signature salt
     @param expiry Signature expiry
     @param expectedGroupId Expected group ID for the signature
     @param multiSignature The multisig encoded signature
     */
    function depositAndStake(
        address to,
        address crucible,
        uint256 amount,
        address stake,
        bytes32 salt,
        uint64 expiry,
        uint64 expectedGroupId,
        bytes memory multiSignature
    ) nonReentrant external {
        require(amount != 0, "CR: amount required");
        require(to != address(0), "CR: to required");
        require(crucible != address(0), "CR: crucible required");
        require(stake != address(0), "CR: stake required");
        if (multiSignature.length != 0) {
            verifyDepositSignature(
                to,
                crucible,
                amount,
                salt,
                expiry,
                expectedGroupId,
                multiSignature
            );
        } else {
            amount = amountFromOpenCap(crucible, amount);
        }

        address token = ICrucibleToken(crucible).baseToken();
        require(SafeAmount.safeTransferFrom(token, msg.sender, crucible, amount) != 0, "CR: nothing transferred");
        require(ICrucibleToken(crucible).deposit(stake) != 0, "CR: nothing depositted");
        IStakeFor(stake).stakeFor(to, crucible);
    }

    /**
     @notice Deposit and add liquidity and stake the LP token in one transaction
     @param to Address of the reciever of stake
     @param crucible The crucible address
     @param pairToken The pair token for liquidity
     @param baseAmount The amount of the base token
     @param pairAmount The amount of the pair token
     @param ammRouter The UNIV2 compatible AMM router for liquidity adding
     @param stake The staking contract address
     @param salt The signature salt
     @param expiry Signature expiry
     @param expectedGroupId Expected group ID for the signature
     @param multiSignature The multisig encoded signature
     */
    function depositAddLiquidityStake(
        address to,
        address crucible,
        address pairToken,
        uint256 baseAmount,
        uint256 pairAmount,
        address ammRouter,
        address stake,
        bytes32 salt,
        uint64 expiry,
        uint256 deadline,
        uint64 expectedGroupId,
        bytes memory multiSignature
    ) nonReentrant amm(ammRouter) external {
        if (multiSignature.length != 0) {
            verifyDepositSig(
                to,
                crucible,
                pairToken,
                baseAmount,
                pairAmount,
                ammRouter,
                stake,
                salt,
                expiry,
                expectedGroupId,
                multiSignature
            );
        } else {
            baseAmount = amountFromOpenCap(crucible, baseAmount);
        }
        {
        pairAmount = SafeAmount.safeTransferFrom(
            pairToken,
            msg.sender,
            address(this),
            pairAmount
        );
        baseAmount = _depositToken(crucible, baseAmount);
        Amounts memory amounts = Amounts({
            base: baseAmount,
            pair: pairAmount,
            isWeth: false
        });
        _addDepositToLiquidity(
            stake,
            crucible,
            pairToken,
            amounts,
            IUniswapV2Router01(ammRouter),
            deadline
        );
        }
        {
            address pool = IUniswapV2Factory(IUniswapV2Router01(ammRouter).factory())
                .getPair(pairToken, crucible);
            require(pool != address(0), "CR: pool does not exist");
            IStakeFor(stake).stakeFor(to, pool);
        }
    }

    /**
     @notice Deposit and add liquidity with ETH and stake the LP token in one transaction
     @param to Address of the reciever of stake
     @param crucible The crucible address
     @param baseAmount The amount of the base token
     @param ammRouter The UNIV2 compatible AMM router for liquidity adding
     @param stake The staking contract address
     @param salt The signature salt
     @param expiry Signature expiry
     @param expectedGroupId Expected group ID for the signature
     @param multiSignature The multisig encoded signature
     */
    function depositAddLiquidityStakeETH(
        address to,
        address crucible,
        uint256 baseAmount,
        address ammRouter,
        address stake,
        bytes32 salt,
        uint64 expiry,
        uint64 deadline,
        uint64 expectedGroupId,
        bytes memory multiSignature
    ) external nonReentrant amm(ammRouter) payable {
        address weth = IUniswapV2Router01(ammRouter).WETH();
        if (multiSignature.length != 0) {
            verifyDepositSig(
                to,
                crucible,
                weth,
                baseAmount,
                msg.value,
                ammRouter,
                stake,
                salt,
                expiry,
                expectedGroupId,
                multiSignature
            );
        } else {
            baseAmount = amountFromOpenCap(crucible, baseAmount);
        }
        IWETH(weth).deposit{value: msg.value}();
        baseAmount = _depositToken(crucible, baseAmount);
        Amounts memory amounts = Amounts({
            base: baseAmount,
            pair: msg.value,
            isWeth: true
        });
        _addDepositToLiquidity(
            stake,
            crucible,
            weth,
            amounts,
            IUniswapV2Router01(ammRouter),
            deadline
        );
        {
            address pool = IUniswapV2Factory(IUniswapV2Router01(ammRouter).factory())
                .getPair(weth, crucible);
            require(pool != address(0), "CR: pool does not exist");
            IStakeFor(stake).stakeFor(to, pool);
        }
    }

    /**
     @notice Sakes for another address
     @dev Use this with crucible users to reduce the need for another approval request
     @param to Address of the reciever of stake
     @param token The token
     @param stake The staking contract address
     @param amount The amount of stake
     */
    function stakeFor(
        address to,
        address token,
        address stake,
        uint256 amount
    ) external {
        require(to != address(0), "CR: Invalid to");
        require(token != address(0), "CR: Invalid token");
        require(stake != address(0), "CR: Invalid stake");
        require(amount != 0, "CR: Invalid amount");
        flushTaxDistributor(token);
        require(SafeAmount.safeTransferFrom(token, msg.sender, stake, amount) != 0, "CR: nothing transferred");
        IStakeFor(stake).stakeFor(to, token);
    }

    bytes32 constant OVERRIDE_FEE_METHOD =
        keccak256(
            "OverrideFee(address crucible,address target,uint8 overrideType,uint64 newFeeX10000,bytes32 salt,uint64 expiry)"
        );
    /**
     @notice Overrides the fee for a given address
     @param crucible The crucible address
     @param target The fee target
     @param overrideType The type of override
     @param newFeeX10000 The new fee on the 10k basis
     @param salt The signature salt
     @param expiry Signature expiry
     @param expectedGroupId Expected group ID for the signature
     @param multiSignature The multisig encoded signature
     */
    function overrideFee(
        address crucible,
        address target,
        ICrucibleToken.OverrideState overrideType,
        uint64 newFeeX10000,
        bytes32 salt,
        uint64 expiry,
        uint64 expectedGroupId,
        bytes memory multiSignature
    ) external expiryRange(expiry) {
        bytes32 message = keccak256(
            abi.encode(
                OVERRIDE_FEE_METHOD,
                crucible,
                target,
                uint8(overrideType),
                newFeeX10000,
                salt,
                expiry
            )
        );
        verifyUniqueSalt(
            message,
            salt,
            expectedGid(crucible, expectedGroupId),
            multiSignature
        );
        ICrucibleToken(crucible).overrideFee(
            target,
            overrideType,
            newFeeX10000
        );
    }

    /**
     @notice Verifies the deposite signature
     @param to The to address
     @param crucible The crucible
     @param amount The amount
     @param salt The salt
     @param expiry The expiry
     @param expectedGroupId The expected group ID
     @param multiSignature The multisig encoded signature
     */
    function verifyDepositSignature(
        address to,
        address crucible,
        uint256 amount,
        bytes32 salt,
        uint64 expiry,
        uint64 expectedGroupId,
        bytes memory multiSignature
    ) private {
        bytes32 message = keccak256(
            abi.encode(DEPOSIT_METHOD, to, crucible, amount, salt, expiry)
        );
        verifyUniqueSalt(
            message,
            salt,
            expectedGid(crucible, expectedGroupId),
            multiSignature
        );
    }

    /**
     @notice Return amount left from the open cap
     @param crucible The crucible
     @param amount The amount
     @return The cap
     */
    function amountFromOpenCap(address crucible, uint256 amount
    ) private returns (uint256) {
        uint256 cap = openCaps[crucible];
        require(cap != 0, "CR: Crucible not open");
        if (cap > amount) {
            cap = cap - amount;
        } else {
            amount = cap;
            cap = 0;
        }
        openCaps[crucible] = cap;
        return amount;
    }

    /**
     @notice Adds deposit to liquidity
     @param to The to address
     @param crucible The crucible
     @param pairToken The pair token
     @param amounts The amounts array
     @param ammRouter The amm router
     @param deadline The deadline
     */
    function _addDepositToLiquidity(
        address to,
        address crucible,
        address pairToken,
        Amounts memory amounts,
        IUniswapV2Router01 ammRouter,
        uint256 deadline
    ) private {
        approveIfRequired(crucible, address(ammRouter), amounts.base);
        approveIfRequired(pairToken, address(ammRouter), amounts.pair);
        (uint256 amountA, uint256 amountB, ) = ammRouter.addLiquidity(
            crucible,
            pairToken,
            amounts.base,
            amounts.pair,
            0,
            0,
            to,
            deadline
        );
        uint256 crucibleLeft = amounts.base - amountA;
        if (crucibleLeft != 0) {
            IERC20(crucible).transfer(msg.sender, crucibleLeft);
        }
        uint256 pairLeft = amounts.pair - amountB;
        if (pairLeft != 0) {
            if (amounts.isWeth) {
                IWETH(pairToken).withdraw(pairLeft);
                SafeAmount.safeTransferETH(msg.sender, pairLeft); // refund dust eth, if any. No need to check the return value
            } else {
                IERC20(pairToken).safeTransfer(msg.sender, pairLeft);
            }
        }
    }

    bytes32 DEPOSIT_ADD_LIQUIDITY_STAKE_METHOD =
        keccak256(
            "DepositAddLiquidityStake(address to,address crucible,address pairToken,uint256 baseAmount,uint256 pairAmount,address ammRouter,address stake,bytes32 salt,uint64 expiry)"
        );
    /**
     @notice Verifies the deposite signature
     @param to The to address
     @param crucible The crucible
     @param pairToken The pair token
     @param baseAmount The base amount
     @param pairAmount The pair amount
     @param ammRouter The amm router
     @param stake The stake
     @param salt The salt
     @param expiry The expiry
     @param expectedGroupId The expected group ID
     @param multiSignature The multisig encoded signature
     */
    function verifyDepositSig(
        address to,
        address crucible,
        address pairToken,
        uint256 baseAmount,
        uint256 pairAmount,
        address ammRouter,
        address stake,
        bytes32 salt,
        uint64 expiry,
        uint64 expectedGroupId,
        bytes memory multiSignature
    ) private expiryRange(expiry) {
        bytes32 message = keccak256(
            abi.encode(
                DEPOSIT_ADD_LIQUIDITY_STAKE_METHOD,
                to,
                crucible,
                pairToken,
                baseAmount,
                pairAmount,
                ammRouter,
                stake,
                salt,
                expiry
            )
        );
        verifyUniqueMessageDigest(
            message,
            expectedGid(crucible, expectedGroupId),
            multiSignature
        );
    }

    /**
     @notice Approves the contract on the amm router if required
     @param token The token
     @param router The router
     @param amount The amount
     */
    function approveIfRequired(
        address token,
        address router,
        uint256 amount
    ) private {
        uint256 allowance = IERC20(token).allowance(address(this), router);
        if (allowance < amount) {
            if (allowance != 0) {
                IERC20(token).safeApprove(router, 0);
            }
            IERC20(token).safeApprove(router, type(uint256).max);
        }
    }

    /**
     @notice Deposits token into crucible
     @param crucible The crucible
     @param amount The amount
     @return deposited The deposited amount
     */
    function _depositToken(address crucible, uint256 amount
    ) private returns (uint256 deposited) {
        address token = ICrucibleToken(crucible).baseToken();
        require(SafeAmount.safeTransferFrom(token, msg.sender, crucible, amount) != 0, "CR: nothing transferred");
        deposited = ICrucibleToken(crucible).deposit(address(this));
        require(deposited != 0, "CR: nothing was deposited");
    }

    /**
     @notice Returns the expected group ID
     @param crucible The crucible
     @param expected Initially expected group ID
     @return gid The expected group ID
     */
    function expectedGid(address crucible, uint64 expected
    ) private view returns (uint64 gid) {
        gid = expected;
        require(
            expected < 256 || delegatedGroupIds[crucible] == expected,
            "CR: bad groupId"
        );
        require(gid != 0, "CR: gov or delegate groupId required");
    }

    /**
     @notice Flushes the tax distributor to allow stakes have fees.
      Otherwise the tax dist balance may cause the safeTransferFrom
      to believe there is a reentrancy attack and fail the transaction.
     @param token The token
     */
    function flushTaxDistributor(address token) private {
        IGeneralTaxDistributor(taxDistributor).distributeTaxAvoidOrigin(token, msg.sender);
    }
}

