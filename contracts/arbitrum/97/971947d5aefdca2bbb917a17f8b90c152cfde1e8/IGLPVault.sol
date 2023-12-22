// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGLPVault {
    //function buyUSDG(address _token, address _receiver) external returns (uint256);
    //function sellUSDG(address _token, address _receiver) external returns (uint256);
    
    function taxBasisPoints() external view returns (uint256);
    function mintBurnFeeBasisPoints() external view returns (uint256);

    //function poolAmounts(address _token) external view returns (uint256);
    function usdgAmounts(address _token) external view returns (uint256);

    function getFeeBasisPoints(address _token, uint256 _usdgDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) external view returns (uint256);

    //Fake for mock tests
    function allowRouter(address _token, uint256 _amount) external;
    function receiveTokenFrom(address _sender, address _token, uint256 _amount) external;
    function sendGlpTo(address sender, uint256 _amount) external;
}
