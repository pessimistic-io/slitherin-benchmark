// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./AccessControl.sol";
import "./ERC20_IERC20.sol";
import "./IDepositWithBeneficiary.sol";
import "./IMeson.sol";
import "./ITransactHook.sol";
import "./Transferer.sol";

contract MesonTransactHooks is ITransactHook, AccessControl, Transferer {
    event SwapSubmitted(uint256 encodedSwap, uint256 amount, address token, address initiator);
    event SwapCanceled(uint256 encodedSwap);

    struct MesonSwapData {
        uint256 encodedSwap;
        bytes32 r;
        bytes32 yParityAndS;
    }

    struct SubmittedSwap {
        uint256 encodedSwap;
        uint256 amount;
        address token;
        address initiator;
    }

    bytes32 public constant HINKAL_ROLE = keccak256("HINKAL_ROLE");

    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    IMeson meson;

    address private currentAuthorizer = address(0);

    mapping(uint256 => SubmittedSwap) private submittedSwaps;

    constructor(address mesonAddress) {
        meson = IMeson(mesonAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function afterTransact(
        CircomData memory circomData,
        bytes calldata metadata
    ) external onlyRole(HINKAL_ROLE) {
        require(circomData.publicAmount < 0, "MTH: Only withdrawals supported");
        require(circomData.recipientAddress == address(this), "MTH: Target of withdrawal should be this contract");
        MesonSwapData memory mesonSwapData = parseMetadata(metadata);
        withdrawToMeson(
            uint256(-1 * circomData.publicAmount),
            circomData.inErc20TokenAddress,
            mesonSwapData.encodedSwap,
            mesonSwapData.r,
            mesonSwapData.yParityAndS
        );
    }

    // Meson smart contract will call this to check the swap is properly authorized
    function isAuthorized(address addr) external view returns (bool) {
        return addr != address(0) && addr == currentAuthorizer;
    }

    // This function should be called by the user directly. He will receive a refund to his EOA
    function cancelSwap(uint256 encodedSwap) external {
        SubmittedSwap memory submittedSwap = submittedSwaps[encodedSwap];
        require(submittedSwap.initiator == msg.sender, "MTH: Caller is not initiator");
        delete submittedSwaps[encodedSwap];
        meson.cancelSwap(encodedSwap);
        transferERC20Token(submittedSwap.token, msg.sender, submittedSwap.amount);
        emit SwapCanceled(encodedSwap);
    }

    function changeMesonApproval(address erc20TokenAddress, bool approved) public onlyRole(WITHDRAWER_ROLE) {
        approveERC20Token(erc20TokenAddress, address(meson), approved ? type(uint256).max : 0);
    }

    function withdraw(address erc20TokenAddress, uint256 amount) public onlyRole(WITHDRAWER_ROLE) {
        transferERC20Token(erc20TokenAddress, msg.sender, amount);
    }

    function withdrawToMeson(
        uint256 amount,
        address token,
        uint256 encodedSwap,
        bytes32 r,
        bytes32 yParityAndS
    ) private {
        currentAuthorizer = tx.origin;
        IERC20(token).approve(address(meson), amount);
        uint200 postingValue = (uint200(uint160(tx.origin)) << 40) + 1;
        meson.postSwapFromContract(encodedSwap, r, yParityAndS, postingValue, address(this));

        currentAuthorizer = address(0); // clear the authorizer
        submittedSwaps[encodedSwap] = SubmittedSwap(encodedSwap, amount, token, tx.origin);

        emit SwapSubmitted(encodedSwap, amount, token, tx.origin);
    }

    function parseMetadata(bytes memory metadata) internal pure returns (MesonSwapData memory) {
        return abi.decode(metadata, (MesonSwapData));
    }
}


