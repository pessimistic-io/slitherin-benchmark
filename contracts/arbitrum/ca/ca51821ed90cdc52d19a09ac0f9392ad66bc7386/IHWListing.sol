// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IHWListing {
    struct Payment {
        address token;
        uint256 amount;
        uint256 listingDate;
    }

    //-----------------//
    //  admin methods  //
    //-----------------//

    function updateRegistry(address _registry) external;

    function withdrawToken(address _token, uint256 _amount) external;

    function withdrawToken(address _token) external;

    function withdrawETH() external;

    function withdrawToken() external;

    //--------------------//
    //  mutative methods  //
    //--------------------//

    function payForListing(address _token, uint256 _amount) external;

    function payForListingEth(uint256 _minTokensOut, uint256 _allowedDelay)
        external
        payable
        returns (uint256[] memory);

    //----------------//
    //  view methods  //
    //----------------//

    function getPayments(address _user)
        external
        view
        returns (Payment[] memory);

    function getLatestPayment(address _user)
        external
        view
        returns (Payment memory);

    function getTokenBalance() external view returns (uint256);
}

