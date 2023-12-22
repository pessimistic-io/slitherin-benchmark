pragma solidity ^0.8.0;

interface Clip {
    function mintLONGGE() external;
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract claimer {
    constructor (address receiver) {
        Clip clip = Clip(0xEbc00D2F9A24e0082308508173e7EB01582B87Dc);
        clip.mintLONGGE();
        clip.transfer(receiver, clip.balanceOf(address(this)));
    }
}

contract BatchMintClips {
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner.");
        _;
    }
    constructor() {
        owner = msg.sender;
    }

    function batchMint(uint count) external {
        for (uint i = 0; i < count;) {
            new claimer(address(this));
            unchecked {
                i++;
            }
        }

        Clip clip = Clip(0xEbc00D2F9A24e0082308508173e7EB01582B87Dc);
        clip.transfer(msg.sender, clip.balanceOf(address(this)) );
    }
}