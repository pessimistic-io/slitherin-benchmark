// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// for bridge only, we should set src/dst the same address
struct SwapDescription {
    address srcToken;   // IERC20
    address dstToken;   // IERC20
    address receiver;
    uint256 amount;
    uint256 minReturnAmount;
}

struct DstChainDescription {
    uint32 dstChainId;
    address dstChainToken;  // IERC20
    uint256 expectedDstChainTokenAmount;
    uint32 slippage;
}

interface IYBridge {
    // according to example, we don't need aggregator address and data. because we mean only bridging
    function swapWithReferrer(
        address aggregatorAdaptor,
        SwapDescription memory swapDesc,
        bytes memory aggregatorData,
        DstChainDescription calldata dstChainDesc,
        address referrer
    ) external payable;
}
