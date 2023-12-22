// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

interface IGLPManager {
    /*
        Since there might be a spread for token pricing, passing in true into the getPrice function returns the maximum price at that point in time, 
        while passing in false returns the minimum price.
    */
    function getPrice(bool _maximise) external view returns (uint256);

    function getAum(bool maximise) external view returns (uint256);

    function getAumInUsdg(bool maximise) external view returns (uint256);

    function vault() external view returns (address);

    function glp() external view returns (address);
}

