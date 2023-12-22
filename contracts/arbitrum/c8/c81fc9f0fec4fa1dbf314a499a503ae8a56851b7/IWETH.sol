// SPDX-License-Identifier: MIT

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function transfer(address to, uint value) external returns (bool);
    function approve(address guy, uint wad) external returns (bool);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function transferFrom(address src, address dst, uint wad) external returns (bool);
}
