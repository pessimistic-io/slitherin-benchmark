// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v2;

import "./NonblockingLzApp.sol";
import "./MerkleProof.sol";
import "./ISwapRouter.sol";
import "./SafeERC20.sol";
import "./WETH.sol";

/// @title A LayerZero example sending a cross chain message from a source chain to a destination chain to increment a counter
contract MintDeposit is NonblockingLzApp {
    using SafeERC20 for IERC20;

    ISwapRouter public immutable swapRouter;
    IERC20 internal immutable WNATIVE;
    IERC20 internal immutable WETH;
    uint192 public inviteListSalePrice;
    uint128 public whalePrice;
    uint128 public whaleMinNFTs;
    uint256 public publicSalePrice;
    uint16 internal immutable dstChainId;

    event Referral(address _minter, string code);

    enum SaleState {
        Inactive, // Neither sale is active
        PublicSale, // Only the public sale is active
        InviteListSale, // Only the invite list sale is active
        InviteListSaleVerify // Invite list sale with verification is active
    }

    SaleState public saleState;

    struct MintData {
        address addr;
        uint256 amount;
    }

    struct SwapParams {
        bytes path;
        address tokenIn;
        uint256 amountIn;
        bool payWithNative;
    }

    mapping(bytes32 => MintData) public mintDataMap;

    // rootHash
    bytes32 public root;

    constructor(
        address _lzEndpoint,
        IERC20 _WNATIVE,
        IERC20 _WETH,
        ISwapRouter _exchange,
        uint256 _publicSalePrice,
        uint192 _inviteListSalePrice,
        uint16 _dstChainId,
        uint128 _whalePrice,
        uint128 _whaleMinNFTs
    ) NonblockingLzApp(_lzEndpoint) {
        swapRouter = _exchange;
        WNATIVE = _WNATIVE;
        WETH = _WETH;
        publicSalePrice = _publicSalePrice;
        inviteListSalePrice = _inviteListSalePrice;
        whalePrice = _whalePrice;
        whaleMinNFTs = _whaleMinNFTs;
        dstChainId = _dstChainId;
    }

    /*
     *  @title Add to whitelist by updating the Merkle tree root
     *  @param root
     *  @dev Caller must be contract owner
     */
    function updateRoot(bytes32 _root) external onlyOwner {
        root = _root;
    }

    /*
     *  @title Adjust Settings
     *  @param each NFT price
     *  @dev caller must be contract owner
     */
    function adjustSettings(
        uint256 _publicSalePrice,
        uint192 _inviteListSalePrice,
        uint128 _whalePrice,
        uint128 _whaleMinNFTs
    ) external onlyOwner {
        publicSalePrice = _publicSalePrice;
        inviteListSalePrice = _inviteListSalePrice;
        whalePrice = _whalePrice;
        whaleMinNFTs = _whaleMinNFTs;
    }

    function setSaleState(uint8 stateNumber) external onlyOwner {
        // Ensure the input number is within the bounds of the SaleState enum
        require(
            stateNumber <= uint8(SaleState.InviteListSaleVerify),
            "Invalid state number"
        );

        // Cast the number to the enum type and update the saleState
        saleState = SaleState(stateNumber);
    }

    // @notice LayerZero endpoint will invoke this function to deliver the message on the destination
    // @param _srcChainId - the source endpoint identifier
    // @param _srcAddress - the source sending contract address from the source chain
    // @param _nonce - the ordered message nonce
    // @param _payload - the signed payload is the UA bytes has encoded to be sent

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {}

    function crossChainPublicMint(
        uint256 _numberOfTokens,
        uint256 _team,
        bytes memory adapterParams,
        SwapParams memory swapParams,
        uint256 reservedForGas,
        string memory code
    ) public payable {
        require(_numberOfTokens > 0, "Incorrect amount");
        require(saleState != SaleState.Inactive, "Not Active");

        uint256 amountEthForMinting = publicSalePrice * _numberOfTokens;
        _swapToWETH(amountEthForMinting, swapParams, reservedForGas);

        _lzSend(
            dstChainId,
            encode(_numberOfTokens, msg.sender, _team),
            payable(msg.sender),
            address(0x0),
            adapterParams,
            reservedForGas
        );

        emit Referral(msg.sender, code);
    }

    function crossChainNFTDiscountMint(
        uint256 _numberOfTokens,
        uint256 _team,
        bytes memory adapterParams,
        SwapParams memory swapParams,
        uint256 reservedForGas,
        string memory code
    ) public payable {
        require(_numberOfTokens > 0, "Incorrect amount");
        require(saleState == SaleState.InviteListSale, "Not Active");

        uint256 amountEthForMinting = inviteListSalePrice * _numberOfTokens;
        _swapToWETH(amountEthForMinting, swapParams, reservedForGas);

        _lzSend(
            dstChainId,
            encode(_numberOfTokens, msg.sender, _team),
            payable(msg.sender),
            address(0x0),
            adapterParams,
            reservedForGas
        );

        emit Referral(msg.sender, code);
    }

    function crossChainNFTWhaleMint(
        uint256 _numberOfTokens,
        uint256 _team,
        bytes memory adapterParams,
        SwapParams memory swapParams,
        uint256 reservedForGas,
        string memory code
    ) public payable {
        require(_numberOfTokens >= whaleMinNFTs, "Not Whale");
        require(saleState != SaleState.Inactive, "Not Active");

        uint256 amountEthForMinting = whalePrice * _numberOfTokens;
        _swapToWETH(amountEthForMinting, swapParams, reservedForGas);

        _lzSend(
            dstChainId,
            encode(_numberOfTokens, msg.sender, _team),
            payable(msg.sender),
            address(0x0),
            adapterParams,
            reservedForGas
        );

        emit Referral(msg.sender, code);
    }

    function getPreApproved(
        uint256 _numberOfTokens,
        uint256 _team,
        bytes memory adapterParams,
        SwapParams memory swapParams,
        bytes32[] calldata _merkleProof,
        string calldata _inviteCode,
        uint256 reservedForGas
    ) public payable {
        require(saleState == SaleState.InviteListSaleVerify, "Not Active");
        require(_numberOfTokens > 0, "Incorrect amount");

        uint256 amountEthForMinting = inviteListSalePrice * _numberOfTokens;
        _swapToWETH(amountEthForMinting, swapParams, reservedForGas);

        {
            if (root != bytes32(0)) {
                bytes32 leaf;
                if (bytes(_inviteCode).length == 0) {
                    leaf = keccak256(abi.encodePacked(msg.sender));
                } else {
                    leaf = keccak256(abi.encodePacked(_inviteCode));
                    MintData storage mintData = mintDataMap[leaf];
                    require(mintData.addr == address(0), "Used Code!");
                    mintData.addr = msg.sender;
                    mintData.amount = _numberOfTokens;
                }

                checkValidity(_merkleProof, leaf);
            }
        }

        _lzSend(
            dstChainId,
            encode(_numberOfTokens, msg.sender, _team),
            payable(msg.sender),
            address(0x0),
            adapterParams,
            reservedForGas
        );
    }

    function _swapToWETH(
        uint256 amountEthForMinting,
        SwapParams memory swapParams,
        uint256 reservedForGas
    ) internal {
        uint256 beforeSwapWETHBalance = WETH.balanceOf(address(this));

        if (swapParams.payWithNative && address(WNATIVE) == address(WETH)) {
            IWETH(address(WNATIVE)).deposit{
                value: msg.value - reservedForGas
            }();
        } else if (
            swapParams.payWithNative && address(WNATIVE) != address(WETH)
        ) {
            IWETH(address(WNATIVE)).deposit{
                value: msg.value - reservedForGas
            }();
            swapTokenForEth(
                swapParams.path,
                swapParams.tokenIn,
                swapParams.amountIn,
                amountEthForMinting
            );
        } else {
            IERC20(swapParams.tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                swapParams.amountIn
            );
            if (swapParams.tokenIn != address(WETH)) {
                swapTokenForEth(
                    swapParams.path,
                    swapParams.tokenIn,
                    swapParams.amountIn,
                    amountEthForMinting
                );
            }
        }

        require(
            WETH.balanceOf(address(this)) >=
                (beforeSwapWETHBalance + amountEthForMinting),
            "Not Enough"
        );
    }

    function encode(
        uint256 nr,
        address addr,
        uint256 team
    ) public pure returns (bytes memory) {
        return abi.encodePacked(nr, addr, team);
    }

    function checkValidity(
        bytes32[] calldata _merkleProof,
        bytes32 leaf
    ) internal view returns (bool) {
        require(
            MerkleProof.verify(_merkleProof, root, leaf),
            "Incorrect proof"
        );
        return true; // Or you can mint tokens here
    }

    function swapTokenForEth(
        bytes memory path,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal {
        // The user needs to approve this contract to spend tokens on their behalf
        IERC20(tokenIn).approve(address(swapRouter), type(uint256).max);

        swapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp + 15, // 15 seconds from now
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum
            })
        );
    }

    function withdrawNativeAsset(
        address payable recipient,
        uint256 amount
    ) external onlyOwner {
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Withdrawal failed");
    }

    function withdrawERC20(
        IERC20 token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        token.safeTransfer(recipient, amount);
    }
}

