//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// https://bia.is/tools/abi2solidity/

// https://curve.readthedocs.io/ref-addresses.html
interface IPoolCurve {
    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy
    ) external;

    //   function exchange ( uint256 i, uint256 j, uint256 dx, uint256 min_dy ) external;
    //   function exchange ( uint256 i, uint256 j, uint256 dx, uint256 min_dy, bool use_eth ) external;
    function fee() external view returns (uint256);

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy,
        bool use_eth
    ) external returns (uint256);

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy,
        bool use_eth,
        address receiver
    ) external returns (uint256);

    // @view
    // @external
    // def get_dy(i: int128, j: int128, dx: uint256) -> uint256:
    //     """
    //     @notice Calculate the current output dy given input dx
    //     @dev Index values can be found via the `coins` public getter method
    //     @param i Index value for the coin to send
    //     @param j Index valie of the coin to recieve
    //     @param dx Amount of `i` being exchanged
    //     @return Amount of `j` predicted
    //     """","name":"coins","inputs":[{"name":"arg0","type":"uint256"}],"outputs":[{"name":"","type":"address"}]

    // function exchange(
    //     int128 i,
    //     int128 j,
    //     uint256 _dx,
    //     uint256 _min_dy
    // ) external returns (uint256);

    // function exchange(
    //     int128 i,
    //     int128 j,
    //     uint256 _dx,
    //     uint256 _min_dy,
    //     address _receiver
    // ) external returns (uint256);

    function coins(uint256 arg0) external view returns (address);

    //stateMutability":"view","type":"function","name":"balances","inputs":[{"name":"arg0","type":"uint256"}],"outputs":[{"name":"","type":"uint256"}],"

    //     @external
    // @nonreentrant('lock')
    // def exchange(
    //     i: int128,
    //     j: int128,
    //     _dx: uint256,
    //     _min_dy: uint256,
    //     _receiver: address = msg.sender,
    // ) -> uint256:
    // nonpayable function exchange inputs [i int128,j int128, _dx uint256, _min_dy uint256,_receiver address],outputs type":"uint256"}]},
}

