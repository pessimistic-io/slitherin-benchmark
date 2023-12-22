// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IHWRegistry {
    struct Whitelist {
        address token;
        uint256 maxAllowed;
    }

    //-----------------//
    //  admin methods  //
    //-----------------//

    function addToWhitelist(address _address, uint256 _maxAllowed) external;

    function removeFromWhitelist(address _address) external;

    function updateWhitelist(address _address, uint256 _maxAllowed) external;

    function setHWEscrow(address _address) external;

    //--------------------//
    //  mutative methods  //
    //--------------------//

    function setNFTGrossRevenue(uint256 _id, uint256 _amount) external;

    //----------------//
    //  view methods  //
    //----------------//

    function isWhitelisted(address _address) external view returns (bool);

    function getWhitelist() external view returns (Whitelist[] memory);

    function getNFTGrossRevenue(uint256 _id) external view returns (uint256);

    function isAllowedAmount(address _address, uint256 _amount)
        external
        view
        returns (bool);

    function counter() external view returns (uint256);
}

