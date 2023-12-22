// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface INativeZapper {
    enum Dex {
        PCS,
        Thena
    }

    function getAmountOut(address _from, uint256 _amount)
        external
        view
        returns (uint256);

    function zapInToken(
        address _from,
        uint256 _amount,
        address _receiver
    ) external returns (uint256 nativeAmount);

    function swapToken(
        address _from,
        address _to,
        uint256 _amount,
        address _receiver
    ) external payable returns (uint256);

    event ZapIn(
        Dex _dex,
        address indexed _from,
        uint256 _amount,
        address indexed _receiver,
        uint256 _amountOut
    );
    event Swapped(
        address indexed _from,
        address indexed _to,
        uint256 _amount,
        address indexed _receiver,
        uint256 _amountOut
    );
    event AccessSet(address indexed _address, bool _status);
    event PairToDexSet(address indexed _from, address indexed _to, Dex _dex);
}

