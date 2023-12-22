// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPositionManager} from "./IPositionManager.sol";
import {ERC20} from "./ERC20.sol";
import {PhvToken} from "./PhvToken.sol";
import {PositionManagerStats} from "./PositionManagerStats.sol";
import {VaultStats} from "./VaultStats.sol";
import {PriceUtils} from "./PriceUtils.sol";
import {TokenExposure} from "./TokenExposure.sol";
import {BASIS_POINTS_DIVISOR, ETH_MULTIPLIER} from "./Constants.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

uint256 constant GAS_PRICE_DIVISOR = 1 * 10 ** 20;

struct VaultInfo {
    IPositionManager[] positionManagers;
    uint256 usdcLiquidity;
}

struct RebalanceQueueData {
    IPositionManager positionManager;
    uint256 usdcAmountToHave;
}

error PositionManagerCannotRebalance(
    address positionManager,
    uint256 amount,
    string errorMessage
);

contract ProtohedgeVault is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    event TotalCompound(uint256 amount);

    string public vaultName;
    ERC20 private usdcToken;
    PhvToken private phvToken;
    IPositionManager[] public positionManagers;
    PriceUtils private priceUtils;
    address private ethPriceFeedAddress;
    uint256 private gasCostPayed;
    // % diff in exposure to rebalance on
    uint256 public rebalancePercent;
    ERC20 public wethToken;

    function initialize(
        string memory _vaultName,
        address _usdcAddress,
        address _priceUtilsAddress,
        address _ethPriceFeedAddress,
        uint256 _rebalancePercent,
        address _wethTokenAddress
    ) public initializer {
        vaultName = _vaultName;
        usdcToken = ERC20(_usdcAddress);
        rebalancePercent = _rebalancePercent;
        priceUtils = PriceUtils(_priceUtilsAddress);
        ethPriceFeedAddress = _ethPriceFeedAddress;
        phvToken = new PhvToken();
        wethToken = ERC20(_wethTokenAddress);

        __Ownable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function vaultWorth() public view returns (uint256) {
        uint256 totalLiquidity = this.getAvailableLiquidity();

        for (uint256 i = 0; i < positionManagers.length; i++) {
            totalLiquidity += positionManagers[i].positionWorth();
        }

        return totalLiquidity;
    }

    function getAvailableLiquidity() public view returns (uint256) {
        return usdcToken.balanceOf(address(this));
    }

    function amountToRebalance() public view returns (uint256) {
        return (vaultWorth() * 8) / 10;
    }

    function positionsWorth() public view returns (uint256) {
        uint256 worth = 0;

        for (uint256 i = 0; i < positionManagers.length; i++) {
            worth += positionManagers[i].positionWorth();
        }

        return worth;
    }

    function addLiquidity(uint256 usdcAmount) external {
        usdcToken.transferFrom(msg.sender, address(this), usdcAmount);
        phvToken.mint(msg.sender, usdcAmount);
    }

    function removeLiquidity(uint256 phvTokenToBurn) external onlyOwner {
        phvToken.burn(msg.sender, phvTokenToBurn);
        uint256 percentOfPool = phvTokenToBurn / phvToken.totalSupply();
        uint256 amountOfUsdc = vaultWorth() * percentOfPool;
        require(
            amountOfUsdc <= getAvailableLiquidity(),
            "Not able to withdraw liquidity."
        );
        usdcToken.transfer(address(this), amountOfUsdc);
    }

    function rebalance(
        RebalanceQueueData[] memory rebalanceQueueData
    ) external onlyOwner {
        uint256 initGas = gasleft();

        for (uint8 i = 0; i < rebalanceQueueData.length; i++) {
            (
                bool canRebalance,
                string memory errorMessage
            ) = rebalanceQueueData[i].positionManager.canRebalance(
                    rebalanceQueueData[i].usdcAmountToHave
                );
            if (!canRebalance) {
                revert PositionManagerCannotRebalance(
                    address(rebalanceQueueData[i].positionManager),
                    rebalanceQueueData[i].usdcAmountToHave,
                    errorMessage
                );
            }
            rebalanceQueueData[i].positionManager.rebalance(
                rebalanceQueueData[i].usdcAmountToHave
            );
        }

        uint256 gasCost = estimateGasCost(initGas);
        gasCostPayed += gasCost;
    }

    function shouldRebalance(
        RebalanceQueueData[] memory rebalanceQueueData
    ) external view returns (bool, string memory) {
        // Only rebalance if
        // 1. All position managers are able to
        // 2. Worth of one or more exposures is not delta neutral (defined as
        for (uint8 i = 0; i < rebalanceQueueData.length; i++) {
            (
                bool canRebalance,
                string memory errorMessage
            ) = rebalanceQueueData[i].positionManager.canRebalance(
                    rebalanceQueueData[i].usdcAmountToHave
                );
            if (!canRebalance) {
                return (false, errorMessage);
            }
        }

        uint256 worth = vaultWorth();
        uint256 availableLiquidity = getAvailableLiquidity();

        if (worth == 0) {
            return (false, "No liquidity to rebalance");
        }

        if ((availableLiquidity * BASIS_POINTS_DIVISOR) / worth > 3000) {
            return (true, "");
        }

        return checkExposureOutOfRange();
    }

    function checkExposureOutOfRange()
        internal
        view
        returns (bool, string memory)
    {
        for (uint8 i = 0; i < positionManagers.length; i++) {
            TokenExposure[] memory positionManagerExposures = positionManagers[
                i
            ].exposures();
            for (uint8 j = 0; j < positionManagerExposures.length; j++) {
                for (uint8 k = 0; k < positionManagers.length; k++) {
                    TokenExposure[]
                        memory positionManagerCompareExposures = positionManagers[
                            k
                        ].exposures();
                    for (
                        uint8 m = 0;
                        m < positionManagerCompareExposures.length;
                        m++
                    ) {
                        if (i == k && j == m) continue;

                        TokenExposure
                            memory exposure1 = positionManagerExposures[j];
                        TokenExposure
                            memory exposure2 = positionManagerCompareExposures[
                                m
                            ];

                        if (exposure1.token != exposure2.token) continue;

                        uint256 exposureAmount1 = abs(exposure1.amount);
                        uint256 exposureAmount2 = abs(exposure2.amount);
                        uint256 average = exposureAmount1 + exposureAmount2 / 2;
                        uint256 upperBound = average +
                            ((average * rebalancePercent) /
                                BASIS_POINTS_DIVISOR);
                        uint256 lowerBound = average -
                            ((average * rebalancePercent) /
                                BASIS_POINTS_DIVISOR);

                        if (
                            exposureAmount1 < lowerBound ||
                            exposureAmount1 > upperBound
                        ) return (true, "");
                        if (
                            exposureAmount2 < lowerBound ||
                            exposureAmount2 > upperBound
                        ) return (true, "");
                    }
                }
            }
        }

        return (false, "No exposure out of range");
    }

    function abs(int256 num) internal pure returns (uint256) {
        return uint256(num < 0 ? -1 * num : num);
    }

    function stats() public view returns (VaultStats memory) {
        PositionManagerStats[]
            memory positionManagersStats = new PositionManagerStats[](
                positionManagers.length
            );

        for (uint256 i = 0; i < positionManagersStats.length; i++) {
            positionManagersStats[i] = positionManagers[i].stats();
        }

        return
            VaultStats({
                vaultAddress: address(this),
                positionManagers: positionManagersStats,
                vaultWorth: vaultWorth(),
                availableLiquidity: getAvailableLiquidity(),
                costBasis: vaultCostBasis(),
                pnl: pnl(),
                positionsWorth: positionsWorth()
            });
    }

    function getPositionManagers()
        public
        view
        returns (IPositionManager[] memory)
    {
        return positionManagers;
    }

    function setPositionManagers(
        IPositionManager[] memory _positionManagers
    ) external onlyOwner {
        positionManagers = _positionManagers;

        for (uint256 index = 0; index < _positionManagers.length; index++) {
            usdcToken.approve(
                address(positionManagers[index]),
                9999999999999999999999999
            );
        }
    }

    function pnl() public view returns (int256) {
        return
            int256(vaultPositionWorth()) +
            int256(compoundedAmount()) -
            int256(vaultCostBasis());
    }

    function compoundedAmount() public view returns (uint256) {
        uint256 ethAmount = wethToken.balanceOf(address(this));
        uint256 ethPrice = priceUtils.getTokenPrice(ethPriceFeedAddress);
        return ((ethAmount * ethPrice) / ETH_MULTIPLIER);
    }

    function vaultPositionWorth() public view returns (uint256) {
        uint256 positionWorth = 0;
        for (uint256 i = 0; i < positionManagers.length; i++) {
            positionWorth += positionManagers[i].positionWorth();
        }

        return positionWorth;
    }

    function vaultCostBasis() public view returns (uint256) {
        uint256 costBasis = 0;
        for (uint256 i = 0; i < positionManagers.length; i++) {
            costBasis += positionManagers[i].costBasis();
        }

        return costBasis;
    }

    function estimateGasCost(
        uint256 initialGasLeft
    ) public view returns (uint256) {
        uint256 gasPrice = tx.gasprice;
        uint256 ethPrice = priceUtils.getTokenPrice(ethPriceFeedAddress);
        return
            (gasPrice * ethPrice * (initialGasLeft - gasleft())) /
            GAS_PRICE_DIVISOR;
    }

    function compound() external onlyOwner returns (uint256) {
        uint256 wethBefore = wethToken.balanceOf(address(this));
        for (uint256 i = 0; i < positionManagers.length; i++) {
            if (positionManagers[i].canCompound()) {
                positionManagers[i].compound();
            }
        }
        uint256 wethAfter = wethToken.balanceOf(address(this));
        uint256 wethCompounded = wethAfter - wethBefore;

        emit TotalCompound(wethCompounded);

        return wethCompounded;
    }

    function liquidate() external onlyOwner {
        for (uint256 i = 0; i < positionManagers.length; i++) {
            positionManagers[i].liquidate();
        }
    }

    function transferToOwner() external onlyOwner {
        usdcToken.transfer(owner(), usdcToken.balanceOf(address(this)));
        wethToken.transfer(owner(), wethToken.balanceOf(address(this)));
    }

    function setWethTokenAddress(address wethTokenAddress) external onlyOwner {
        wethToken = ERC20(wethTokenAddress);
    }
}

