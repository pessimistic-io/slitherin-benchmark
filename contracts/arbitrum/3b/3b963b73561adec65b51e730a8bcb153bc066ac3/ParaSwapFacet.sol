// SPDX-License-Identifier: BUSL-1.1
// Last deployed from commit: 9831899e5e0f2fa1b783ca992c0700e8ee549978;
pragma solidity 0.8.17;

import "./IERC20.sol";

import "./IParaSwapRouter.sol";
import "./ReentrancyGuardKeccak.sol";
import "./Math.sol";
import {DiamondStorageLib} from "./DiamondStorageLib.sol";
import "./SolvencyMethods.sol";
import "./ITokenManager.sol";

//This path is updated during deployment
import "./DeploymentConstants.sol";

contract ParaSwapFacet is ReentrancyGuardKeccak, SolvencyMethods {
    using TransferHelper for address;

    address private constant PARA_TRANSFER_PROXY = 0x216B4B4Ba9F3e719726886d34a177484278Bfcae;
    address private constant PARA_ROUTER = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;

    struct SwapTokensDetails {
        bytes32 tokenSoldSymbol;
        bytes32 tokenBoughtSymbol;
        IERC20Metadata soldToken;
        IERC20Metadata boughtToken;
        uint256 initialSoldTokenBalance;
        uint256 initialBoughtTokenBalance;
    }

    function getInitialTokensDetails(address _soldTokenAddress, address _boughtTokenAddress) internal view returns (SwapTokensDetails memory){
        ITokenManager tokenManager = DeploymentConstants.getTokenManager();

        if (_boughtTokenAddress == 0xaE64d55a6f09E4263421737397D1fdFA71896a69) {
            _boughtTokenAddress = 0x9e295B5B976a184B14aD8cd72413aD846C299660;
        }

        if (_soldTokenAddress == 0xaE64d55a6f09E4263421737397D1fdFA71896a69) {
            _soldTokenAddress = 0x9e295B5B976a184B14aD8cd72413aD846C299660;
        }

        bytes32 _tokenSoldSymbol = tokenManager.tokenAddressToSymbol(_soldTokenAddress);
        bytes32 _tokenBoughtSymbol = tokenManager.tokenAddressToSymbol(_boughtTokenAddress);

        require(tokenManager.isTokenAssetActive(_boughtTokenAddress), "Asset not supported.");

        IERC20Metadata _soldToken = IERC20Metadata(_soldTokenAddress);
        IERC20Metadata _boughtToken = IERC20Metadata(_boughtTokenAddress);

        return SwapTokensDetails({
            tokenSoldSymbol: _tokenSoldSymbol,
            tokenBoughtSymbol: _tokenBoughtSymbol,
            soldToken: _soldToken,
            boughtToken: _boughtToken,
            initialSoldTokenBalance: _soldToken.balanceOf(address(this)),
            initialBoughtTokenBalance: _boughtToken.balanceOf(address(this))
        });
    }

    function paraSwap(IParaSwapRouter.SimpleData memory data) external nonReentrant onlyOwner noBorrowInTheSameBlock recalculateAssetsExposure remainsSolvent{
        SwapTokensDetails memory swapTokensDetails = getInitialTokensDetails(data.fromToken, data.toToken);

        uint256 amount = Math.min(swapTokensDetails.soldToken.balanceOf(address(this)), data.fromAmount);
        require(amount > 0, "Amount of tokens to sell has to be greater than 0");

        address(swapTokensDetails.soldToken).safeApprove(PARA_TRANSFER_PROXY, 0);
        address(swapTokensDetails.soldToken).safeApprove(PARA_TRANSFER_PROXY, amount);

        IParaSwapRouter router = IParaSwapRouter(PARA_ROUTER);

        router.simpleSwap(data);

        // Add asset to ownedAssets
        if (swapTokensDetails.boughtToken.balanceOf(address(this)) > 0) {
            DiamondStorageLib.addOwnedAsset(swapTokensDetails.tokenBoughtSymbol, address(swapTokensDetails.boughtToken));
        }

        // Remove asset from ownedAssets if the asset balance is 0 after the swap
        if (swapTokensDetails.soldToken.balanceOf(address(this)) == 0) {
            DiamondStorageLib.removeOwnedAsset(swapTokensDetails.tokenSoldSymbol);
        }

        uint256 boughtTokenFinalAmount = swapTokensDetails.boughtToken.balanceOf(address(this)) - swapTokensDetails.initialBoughtTokenBalance;

        emit Swap(
            msg.sender,
            swapTokensDetails.tokenSoldSymbol,
            swapTokensDetails.tokenBoughtSymbol,
            swapTokensDetails.initialSoldTokenBalance - swapTokensDetails.soldToken.balanceOf(address(this)),
            boughtTokenFinalAmount,
            block.timestamp
        );

    }

    modifier onlyOwner() {
        DiamondStorageLib.enforceIsContractOwner();
        _;
    }

    /**
     * @dev emitted after a swap of assets
     * @param user the address of user making the purchase
     * @param soldAsset sold by the user
     * @param boughtAsset bought by the user
     * @param amountSold amount of tokens sold
     * @param amountBought amount of tokens bought
     * @param timestamp time of the swap
     **/
    event Swap(address indexed user, bytes32 indexed soldAsset, bytes32 indexed boughtAsset, uint256 amountSold, uint256 amountBought, uint256 timestamp);
}

