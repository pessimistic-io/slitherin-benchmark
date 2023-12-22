//SPDX-License-Identifier: Unlicense

pragma solidity 0.8.18;

import {IERC721} from "./IERC721.sol";
import {IERC20} from "./IERC20.sol";

interface IPaymentReceiver {
    error NotAllowedToExchangeGems(address wallet);
    error AfterDeadline();
    error TokenNotExists();
    error AddressZero();

    event GemsPurchased(
        address indexed wallet,
        IERC721 indexed collection,
        uint256 indexed tokenId,
        address by,
        uint256 amount,
        uint256 price
    );

    function treasury() external view returns (address);

    function collection() external view returns (IERC721);

    function paymentToken() external view returns (IERC20);

    function buyGems(
        address _wallet,
        uint256 _tokenId,
        uint256 _amount,
        uint256 _price,
        uint256 _deadline,
        bytes calldata _signature
    ) external;

    function buyGemsHash(
        address _wallet,
        uint256 _tokenId,
        uint256 _amount,
        uint256 _price,
        uint256 _deadline
    ) external view returns (bytes32);
}

