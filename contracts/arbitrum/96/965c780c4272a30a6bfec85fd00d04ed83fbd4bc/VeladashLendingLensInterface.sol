pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

import "./ERC20_IERC20.sol";
import "./AggregatorV2V3Interface.sol";

interface IPriceOracle {
    function getUnderlyingPrice(address vela) external view returns (uint256);
    function getFeed(string calldata symbol) external view returns (address);
}

interface IJumpRateModelV2 {
    function utilizationRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external pure returns (uint256);
}

interface IInterestRateModel {
    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view returns (uint256);

    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256);
}

interface IComptroller {
    function oracle() external view returns (address);

    function getAssetsIn(address account) external view returns (address[] memory);

    function getAccountLiquidity(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    struct Market {
        bool isListed;
        uint256 collateralFactorMantissa;
    }

    function markets(address vToken) external view returns (Market memory);

    function borrowCaps(address vToken) external view returns (uint256);

    function borrowGuardianPaused(address vToken) external view returns (bool);

}

interface IGovernor {
    struct Receipt {
        bool hasVoted;
        bool support;
        uint96 votes;
    }

    function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory);

    function proposals(uint256 proposalId)
        external
        view
        returns (
            uint256,
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        );

    function getActions(uint256 proposalId)
        external
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        );
}

interface IERC20Extented is IERC20 {
    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);
}

interface IVToken {
    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function underlying() external view returns (address);

    function balanceOf(address owner) external view returns (uint256);

    function getCash() external view returns (uint256);

    function totalBorrows() external view returns (uint256);

    function totalReserves() external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function supplyRatePerBlock() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function reserveFactorMantissa() external view returns (uint256);

    function comptroller() external view returns (address);

    function borrowBalanceStored(address account) external view returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);

    function interestRateModel() external view returns (address);
}

