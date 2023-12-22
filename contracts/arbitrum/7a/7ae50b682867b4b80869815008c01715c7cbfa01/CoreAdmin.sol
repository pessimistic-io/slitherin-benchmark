// SPDX-License-Identifier: UNLICENSE
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";

import "./Constant.sol";

import "./ICore.sol";
import "./IGRVDistributor.sol";
import "./IPriceCalculator.sol";
import "./IGToken.sol";
import "./IRebateDistributor.sol";

abstract contract CoreAdmin is ICore, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /* ========== STATE VARIABLES ========== */

    address public keeper;
    address public override nftCore;
    address public override validator;
    address public override rebateDistributor;
    IGRVDistributor public grvDistributor;
    IPriceCalculator public priceCalculator;

    address[] public markets; // gTokenAddress[]
    mapping(address => Constant.MarketInfo) public marketInfos; // (gTokenAddress => MarketInfo)

    uint256 public override closeFactor;
    uint256 public override liquidationIncentive;

    /* ========== VARIABLE GAP ========== */

    uint256[49] private __gap;

    /* ========== MODIFIERS ========== */

    /// @dev sender 가 keeper address 인지 검증
    modifier onlyKeeper() {
        require(msg.sender == keeper || msg.sender == owner(), "Core: caller is not the owner or keeper");
        _;
    }

    /// @dev Market 에 list 된 gToken address 인지 검증
    /// @param gToken gToken address
    modifier onlyListedMarket(address gToken) {
        require(marketInfos[gToken].isListed, "Core: invalid market");
        _;
    }

    modifier onlyNftCore() {
        require(msg.sender == nftCore, "Core: caller is not the nft core");
        _;
    }

    /* ========== INITIALIZER ========== */

    function __Core_init() internal initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        closeFactor = 5e17; // 0.5
        liquidationIncentive = 115e16; // 1.15
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice keeper address 변경
    /// @dev keeper address 에서만 요청 가능
    /// @param _keeper 새로운 keeper address
    function setKeeper(address _keeper) external onlyKeeper {
        require(_keeper != address(0), "Core: invalid keeper address");
        keeper = _keeper;
        emit KeeperUpdated(_keeper);
    }

    function setNftCore(address _nftCore) external onlyKeeper {
        require(_nftCore != address(0), "Core: invalid nft core address");
        nftCore = _nftCore;
        emit NftCoreUpdated(_nftCore);
    }

    /// @notice validator 변경
    /// @dev keeper address 에서만 요청 가능
    /// @param _validator 새로운 validator address
    function setValidator(address _validator) external onlyKeeper {
        require(_validator != address(0), "Core: invalid validator address");
        validator = _validator;
        emit ValidatorUpdated(_validator);
    }

    /// @notice grvDistributor 변경
    /// @dev keeper address 에서만 요청 가능
    /// @param _grvDistributor 새로운 grvDistributor address
    function setGRVDistributor(address _grvDistributor) external onlyKeeper {
        require(_grvDistributor != address(0), "Core: invalid grvDistributor address");
        grvDistributor = IGRVDistributor(_grvDistributor);
        emit GRVDistributorUpdated(_grvDistributor);
    }

    function setRebateDistributor(address _rebateDistributor) external onlyKeeper {
        require(_rebateDistributor != address(0), "Core: invalid rebateDistributor address");
        rebateDistributor = _rebateDistributor;
        emit RebateDistributorUpdated(_rebateDistributor);
    }

    /// @notice close factor 변경
    /// @dev keeper address 에서만 요청 가능
    /// @param newCloseFactor 새로운 close factor 값 (TBD)
    function setCloseFactor(uint256 newCloseFactor) external onlyKeeper {
        require(
            newCloseFactor >= Constant.CLOSE_FACTOR_MIN && newCloseFactor <= Constant.CLOSE_FACTOR_MAX,
            "Core: invalid close factor"
        );
        closeFactor = newCloseFactor;
        emit CloseFactorUpdated(newCloseFactor);
    }

    /// @notice Market collateral factor (담보 인정 비율) 변경
    /// @dev keeper address 에서만 요청 가능
    /// @param gToken gToken address
    /// @param newCollateralFactor collateral factor (담보 인정 비율)
    function setCollateralFactor(
        address gToken,
        uint256 newCollateralFactor
    ) external onlyKeeper onlyListedMarket(gToken) {
        require(newCollateralFactor <= Constant.COLLATERAL_FACTOR_MAX, "Core: invalid collateral factor");
        if (newCollateralFactor != 0 && priceCalculator.getUnderlyingPrice(gToken) == 0) {
            revert("Core: invalid underlying price");
        }

        marketInfos[gToken].collateralFactor = newCollateralFactor;
        emit CollateralFactorUpdated(gToken, newCollateralFactor);
    }

    /// @notice 청산 인센티브 설정
    /// @dev keeper address 에서만 요청 가능
    /// @param newLiquidationIncentive 새로운 청산 인센티브 값 (TBD)
    function setLiquidationIncentive(uint256 newLiquidationIncentive) external onlyKeeper {
        liquidationIncentive = newLiquidationIncentive;
        emit LiquidationIncentiveUpdated(newLiquidationIncentive);
    }

    /// @notice Market supply cap 변경
    /// @dev keeper address 에서만 요청 가능
    /// @param gTokens gToken addresses
    /// @param newSupplyCaps new supply caps in array
    function setMarketSupplyCaps(address[] calldata gTokens, uint256[] calldata newSupplyCaps) external onlyKeeper {
        require(gTokens.length != 0 && gTokens.length == newSupplyCaps.length, "Core: invalid data");

        for (uint256 i = 0; i < gTokens.length; i++) {
            marketInfos[gTokens[i]].supplyCap = newSupplyCaps[i];
            emit SupplyCapUpdated(gTokens[i], newSupplyCaps[i]);
        }
    }

    /// @notice Market borrow cap 변경
    /// @dev keeper address 에서만 요청 가능
    /// @param gTokens gToken addresses
    /// @param newBorrowCaps new borrow caps in array
    function setMarketBorrowCaps(address[] calldata gTokens, uint256[] calldata newBorrowCaps) external onlyKeeper {
        require(gTokens.length != 0 && gTokens.length == newBorrowCaps.length, "Core: invalid data");

        for (uint256 i = 0; i < gTokens.length; i++) {
            marketInfos[gTokens[i]].borrowCap = newBorrowCaps[i];
            emit BorrowCapUpdated(gTokens[i], newBorrowCaps[i]);
        }
    }

    /// @notice Market 추가
    /// @dev keeper address 에서만 요청 가능
    /// @param gToken gToken address
    /// @param supplyCap supply cap
    /// @param borrowCap borrow cap
    /// @param collateralFactor collateral factor (담보 인정 비율)
    function listMarket(
        address payable gToken,
        uint256 supplyCap,
        uint256 borrowCap,
        uint256 collateralFactor
    ) external onlyKeeper {
        require(!marketInfos[gToken].isListed, "Core: already listed market");
        for (uint256 i = 0; i < markets.length; i++) {
            require(markets[i] != gToken, "Core: already listed market");
        }

        marketInfos[gToken] = Constant.MarketInfo({
            isListed: true,
            supplyCap: supplyCap,
            borrowCap: borrowCap,
            collateralFactor: collateralFactor
        });
        markets.push(gToken);
        emit MarketListed(gToken);
    }

    /// @notice Market 제거
    /// @dev keeper address 에서만 요청 가능
    /// @param gToken gToken address
    function removeMarket(address payable gToken) external onlyKeeper {
        require(marketInfos[gToken].isListed, "Core: unlisted market");
        require(IGToken(gToken).totalSupply() == 0 && IGToken(gToken).totalBorrow() == 0, "Core: cannot remove market");

        uint256 length = markets.length;
        for (uint256 i = 0; i < length; i++) {
            if (markets[i] == gToken) {
                markets[i] = markets[length - 1];
                markets.pop();
                delete marketInfos[gToken];
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
}

