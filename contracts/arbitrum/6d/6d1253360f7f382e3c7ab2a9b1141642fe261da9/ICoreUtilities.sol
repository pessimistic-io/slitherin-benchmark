// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20Stable.sol";
import "./IOracleConnector.sol";
import "./IFoxifyAffiliation.sol";
import "./ICoreConfiguration.sol";
import "./ISwapperConnector.sol";

interface ICoreUtilities {
    struct AffiliationUserData {
        uint256 activeId;
        uint256 team;
        uint256 discount;
        IFoxifyAffiliation.NFTData nftData;
    }

    function calculateStableFee(
        address affiliationUser,
        uint256 amount,
        uint256 fee
    ) external view returns (AffiliationUserData memory affiliationUserData_, uint256 fee_);
    function configuration() external view returns (ICoreConfiguration);
    function getAndValidateRoundForAutoResolve(
        uint256 roundId,
        uint256 endTime,
        address oracle
    ) external view returns (bool invalidRound, uint256 price);
    function getAndValidateRoundForAccept(address oracle, uint256 endTime) external view returns (uint256 price);

    function initialize(address configuration_) external returns (bool);
    function swap(address recipient, uint256 winnerTotalAmount) external returns (uint256 amountIn);
}

