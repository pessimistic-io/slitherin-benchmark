// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;

import "./ERC20_IERC20.sol";

interface IERC20Mintable {

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;
}

interface IERC20Pegged {

    function getOrigin() external view returns (uint256, address);
}

interface IERC20Extra {

    function name() external returns (string memory);

    function decimals() external returns (uint8);

    function symbol() external returns (string memory);
}

interface IERC20MetadataChangeable {

    event NameChanged(string prevValue, string newValue);

    event SymbolChanged(string prevValue, string newValue);

    function changeName(bytes32) external;

    function changeSymbol(bytes32) external;
}

interface IERC20InternetBond {

    function ratio() external view returns (uint256);

    function isRebasing() external view returns (bool);
}

