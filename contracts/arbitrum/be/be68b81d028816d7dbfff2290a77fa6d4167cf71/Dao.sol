// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./veNimbusToken.sol";
import "./CloudManager.sol";
import "./CloudTrait.sol";
import "./SafeMath.sol";

contract NimbusDao is Ownable {
    using SafeMath for uint256;

    veNimbusToken public veToken;
    CloudManager public cm;

    uint256 public startDate;
    uint256 public endDate;
    uint256 public range = 12 hours;

    mapping(address => uint256) public lastVote;
    mapping(Kind => uint256) public votes;

    enum Kind {
        Double,
        Stand,
        Divide
    }

    event Voted(Kind _kind);

    constructor(veNimbusToken _veToken, CloudManager _cm) {
        veToken = _veToken;
        cm = _cm;
        startDate = block.timestamp;
        endDate = startDate + range;
    }

    function vote(Kind _kind) external {
        require(
            lastVote[msg.sender] < startDate &&
            block.timestamp >= startDate &&
                block.timestamp < endDate,
            "FBD: Vote is closed"
        );
        lastVote[msg.sender] = block.timestamp;
        votes[_kind] += veToken.balanceOf(msg.sender);
        emit Voted(_kind);
    }

    function resetVote() external {
        require(block.timestamp >= endDate, "FBD: Should wait til end of vote");
        startDate = block.timestamp + range;
        endDate = startDate + range;
        if (
            votes[Kind.Double] > votes[Kind.Divide] &&
            votes[Kind.Double] > votes[Kind.Stand]
        ) {
            double();
        } else if (
            votes[Kind.Divide] > votes[Kind.Double] &&
            votes[Kind.Divide] > votes[Kind.Stand]
        ) {
            divide();
        }
        votes[Kind.Double] = 0;
        votes[Kind.Stand] = 0;
        votes[Kind.Divide] = 0;
    }

    function double() private {
        uint256[] memory aprs = cm.getAPR();
        uint256 l0 = aprs[0].mul(2);
        uint256 l1 = aprs[1].mul(2);
        uint256 l2 = aprs[2].mul(2);
        cm.setYield(
            l0,
            l1,
            l2
            );
    }

    function divide() private {
        uint256[] memory aprs = cm.getAPR();
        uint256 l0 = aprs[0].div(2);
        uint256 l1 = aprs[1].div(2);
        uint256 l2 = aprs[2].div(2);
        cm.setYield(
            l0,
            l1,
            l2
            );
    }

    function getAPR() external view returns(uint256[] memory) {
        return cm.getAPR();
    }

    function setToken(veNimbusToken _veToken) external onlyOwner {
        veToken = _veToken;
    }

    function setCM(CloudManager _cm) external onlyOwner {
        cm = _cm;
    }
}

