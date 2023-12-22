import "./Clones.sol";

interface BOX {
    function boxFanMint() external virtual;

    function transfer(
        address to,
        uint256 amount
    ) external virtual returns (bool);

    function balanceOf(address account) external virtual returns (uint256);
}

contract A {
    address immutable box = 0xd1aDcDEe980Fe7a3988b2699cD813A5848145998;

    function mint(address _to) external {
        BOX(box).boxFanMint();
        BOX(box).transfer(_to, BOX(box).balanceOf(address(this)));
    }
}

contract MintBatch {
    address public imple;

    constructor() {
        imple = address(new A());
    }

    function mintBatch(uint256 _times) external {
        for (uint256 i = 0; i < _times; i++) {
            address box = Clones.clone(imple);
            A(box).mint(msg.sender);
        }
    }
}

