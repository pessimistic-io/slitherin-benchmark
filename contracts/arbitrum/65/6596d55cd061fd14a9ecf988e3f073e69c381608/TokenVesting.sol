pragma solidity 0.7.6;

import "./SafeMath.sol";
import "./IMultiFeeDistribution.sol";

contract TokenVesting {
    using SafeMath for uint256;

    uint256 public startTime;
    uint256 public constant duration = 86400 * 365;
    uint256 public immutable maxMintableTokens;
    uint256 public mintedTokens;
    IMultiFeeDistribution public minter;
    address public owner;

    address private teamReceiver;
    uint256 public constant teamPreMint = 20000000000000000000000000;
    uint256 private constant threeMonthsDuration = 86400 * 90;

    struct Vest {
        uint256 total;
        uint256 claimed;
    }

    mapping(address => Vest) public vests;

    constructor(
        IMultiFeeDistribution _minter,
        uint256 _maxMintable,
        address[] memory _receivers,
        uint256[] memory _amounts
    ) {
        require(_receivers.length == _amounts.length);
        minter = _minter;
        uint256 mintable;
        for (uint256 i = 0; i < _receivers.length; i++) {
            require(vests[_receivers[i]].total == 0);
            mintable = mintable.add(_amounts[i]);
            vests[_receivers[i]].total = _amounts[i];
        }
        require(mintable == _maxMintable);
        maxMintableTokens = mintable;
        teamReceiver = _receivers[0];
        owner = msg.sender;
    }

    function start() external {
        require(msg.sender == owner);
        require(startTime == 0);
        minter.mint(teamReceiver, teamPreMint, false);
        startTime = block.timestamp;
    }

    function claimable(address _claimer) external view returns (uint256) {
        if (startTime == 0) return 0;
        Vest storage v = vests[_claimer];
        uint256 elapsedTime = block.timestamp.sub(startTime);
        if (elapsedTime < threeMonthsDuration && _claimer == teamReceiver)
            return 0;
        if (elapsedTime > duration) elapsedTime = duration;
        uint256 claimable = v.total.mul(elapsedTime).div(duration);
        return claimable.sub(v.claimed);
    }

    function claim(address _receiver) external {
        require(startTime != 0);
        Vest storage v = vests[msg.sender];
        uint256 elapsedTime = block.timestamp.sub(startTime);
        if (elapsedTime < threeMonthsDuration && _receiver == teamReceiver)
            return;
        if (elapsedTime > duration) elapsedTime = duration;
        uint256 claimable = v.total.mul(elapsedTime).div(duration);
        if (claimable > v.claimed) {
            uint256 amount = claimable.sub(v.claimed);
            mintedTokens = mintedTokens.add(amount);
            require(mintedTokens <= maxMintableTokens);
            minter.mint(_receiver, amount, false);
            v.claimed = claimable;
        }
    }
}

