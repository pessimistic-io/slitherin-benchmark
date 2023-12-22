// SPDX-License-Identifier: UNLICENSE
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./library_Math.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC721EnumerableUpgradeable.sol";
import "./IERC721Upgradeable.sol";
import "./IERC721ReceiverUpgradeable.sol";

import "./Constant.sol";

import "./INftCore.sol";
import "./INFTOracle.sol";
import "./IGToken.sol";
import "./IGNft.sol";
import "./ICore.sol";
import "./ILendPoolLoan.sol";
import "./INftValidator.sol";

abstract contract NftCoreAdmin is INftCore, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, IERC721ReceiverUpgradeable {

    /* ========== STATE VARIABLES ========== */

    INFTOracle public nftOracle;
    ICore public core;
    ILendPoolLoan public lendPoolLoan;
    INftValidator public validator;

    address public borrowMarket;
    address public keeper;
    address public treasury;

    address[] public markets; // gNftAddress[]
    mapping(address => Constant.NftMarketInfo) public marketInfos; // (gNftAddress => NftMarketInfo)

    /* ========== MODIFIERS ========== */

    modifier onlyKeeper() {
        require(msg.sender == keeper || msg.sender == owner(), "NftCore: caller is not the owner or keeper");
        _;
    }

    modifier onlyListedMarket(address gNft) {
        require(marketInfos[gNft].isListed, "NftCore: invalid market");
        _;
    }

    /* ========== INITIALIZER ========== */

    receive() external payable {}

    function __NftCore_init(
        address _nftOracle,
        address _borrowMarket,
        address _core,
        address _treasury
    ) internal initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        nftOracle = INFTOracle(_nftOracle);
        core = ICore(_core);
        borrowMarket = _borrowMarket;
        treasury = _treasury;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setKeeper(address _keeper) external onlyKeeper {
        require(_keeper != address(0), "NftCore: invalid keeper address");
        keeper = _keeper;
        emit KeeperUpdated(_keeper);
    }

    function setTreasury(address _treasury) external onlyKeeper {
        require(_treasury != address(0), "NftCore: invalid treasury address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setValidator(address _validator) external onlyKeeper {
        require(_validator != address(0), "NftCore: invalid validator address");
        validator = INftValidator(_validator);
        emit ValidatorUpdated(_validator);
    }

    function setNftOracle(address _nftOracle) external onlyKeeper {
        require(_nftOracle != address(0), "NftCore: invalid nft oracle address");
        nftOracle = INFTOracle(_nftOracle);
        emit NftOracleUpdated(_nftOracle);
    }

    function setLendPoolLoan(address _lendPoolLoan) external onlyKeeper {
        require(_lendPoolLoan != address(0), "NftCore: invalid lend pool loan address");
        lendPoolLoan = ILendPoolLoan(_lendPoolLoan);
        emit LendPoolLoanUpdated(_lendPoolLoan);
    }

    function setCore(address _core) external onlyKeeper {
        require(_core != address(0), "NftCore: invalid core address");
        core = ICore(_core);
        emit CoreUpdated(_core);
    }

    function setCollateralFactor(
        address gNft,
        uint256 newCollateralFactor
    ) external onlyKeeper onlyListedMarket(gNft) {
        require(newCollateralFactor <= Constant.COLLATERAL_FACTOR_MAX, "NftCore: invalid collateral factor");
        if (newCollateralFactor != 0 && nftOracle.getUnderlyingPrice(gNft) == 0) {
            revert("NftCore: invalid underlying price");
        }

        marketInfos[gNft].collateralFactor = newCollateralFactor;
        emit CollateralFactorUpdated(gNft, newCollateralFactor);
    }

    function setMarketSupplyCaps(address[] calldata gNfts, uint256[] calldata newSupplyCaps) external onlyKeeper {
        require(gNfts.length != 0 && gNfts.length == newSupplyCaps.length, "NftCore: invalid data");

        for (uint256 i = 0; i < gNfts.length; i++) {
            marketInfos[gNfts[i]].supplyCap = newSupplyCaps[i];
            emit SupplyCapUpdated(gNfts[i], newSupplyCaps[i]);
        }
    }

    function setMarketBorrowCaps(address[] calldata gNfts, uint256[] calldata newBorrowCaps) external onlyKeeper {
        require(gNfts.length != 0 && gNfts.length == newBorrowCaps.length, "NftCore: invalid data");

        for (uint256 i = 0; i < gNfts.length; i++) {
            marketInfos[gNfts[i]].borrowCap = newBorrowCaps[i];
            emit BorrowCapUpdated(gNfts[i], newBorrowCaps[i]);
        }
    }

    function setLiquidationThreshold(
        address gNft,
        uint256 newLiquidationThreshold
    ) external onlyKeeper onlyListedMarket(gNft) {
        require(newLiquidationThreshold <= Constant.LIQUIDATION_THRESHOLD_MAX, "NftCore: invalid liquidation threshold");
        if (newLiquidationThreshold != 0 && nftOracle.getUnderlyingPrice(gNft) == 0) {
            revert("NftCore: invalid underlying price");
        }

        marketInfos[gNft].liquidationThreshold = newLiquidationThreshold;
        emit LiquidationThresholdUpdated(gNft, newLiquidationThreshold);
    }

    function setLiquidationBonus(
        address gNft,
        uint256 newLiquidationBonus
    ) external onlyKeeper onlyListedMarket(gNft) {
        require(newLiquidationBonus <= Constant.LIQUIDATION_BONUS_MAX, "NftCore: invalid liquidation bonus");
        if (newLiquidationBonus != 0 && nftOracle.getUnderlyingPrice(gNft) == 0) {
            revert("NftCore: invalid underlying price");
        }

        marketInfos[gNft].liquidationBonus = newLiquidationBonus;
        emit LiquidationBonusUpdated(gNft, newLiquidationBonus);
    }

    function listMarket(
        address gNft,
        uint256 supplyCap,
        uint256 borrowCap,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    ) external onlyKeeper {
        require(!marketInfos[gNft].isListed, "NftCore: already listed market");
        for (uint256 i = 0; i < markets.length; i++) {
            require(markets[i] != gNft, "NftCore: already listed market");
        }

        marketInfos[gNft] = Constant.NftMarketInfo({
            isListed: true,
            supplyCap: supplyCap,
            borrowCap: borrowCap,
            collateralFactor: collateralFactor,
            liquidationThreshold: liquidationThreshold,
            liquidationBonus: liquidationBonus
        });

        address _underlying = IGNft(gNft).underlying();

        IERC721Upgradeable(_underlying).setApprovalForAll(address(lendPoolLoan), true);
        lendPoolLoan.initNft(_underlying, gNft);

        markets.push(gNft);
        emit MarketListed(gNft);
    }

    function removeMarket(address gNft) external onlyKeeper {
        require(marketInfos[gNft].isListed, "NftCore: unlisted market");
        require(IERC721EnumerableUpgradeable(gNft).totalSupply() == 0, "NftCore: cannot remove market");

        uint256 length = markets.length;
        for (uint256 i = 0; i < length; i++) {
            if (markets[i] == gNft) {
                markets[i] = markets[length - 1];
                markets.pop();
                delete marketInfos[gNft];
                break;
            }
        }
    }

    function pause() external onlyKeeper {
        _pause();
    }

    function unpause() external onlyKeeper {
        _unpause();
    }

    /* ========== VIEWS ========== */

    function getLendPoolLoan() external view override returns (address) {
        return address(lendPoolLoan);
    }

    function getNftOracle() external view override returns (address) {
        return address(nftOracle);
    }

    /* ========== RECEIVER FUNCTIONS ========== */

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        operator;
        from;
        tokenId;
        data;
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }
}

