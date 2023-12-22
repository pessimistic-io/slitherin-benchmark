interface IDuelPepes {
    struct Duel {
      // unique identifier for duel (salt)
      bytes32 identifier;
      // 0 index = creator, 1 index = challenger
      address[2] duellors;
      // Wager amount in WETH
      uint wager;
      // Fees at the time of duel creation
      uint fees;
      // Initial hashed move set signature when creating duel
      bytes initialMovesSignature;
      // Moves selected by duel participants
      // 0 index = creator, 1 index = challenger
      uint[5][2] moves;
      // Who won the duel
      bool isCreatorWinner;
      // 0 index - Time created, 1 index - time challenged, 2 - time decided
      uint[3] timestamps;
    }

    enum Moves {
      // Accurate [1, 1, 0]
      Punch,
      // Strength [2, 0, 0]
      Kick,
      // Defense [0, 0, 3]
      Block,
      // Special attack [3, 0, 0]
      Special
    }

    function getDuel(uint _id)
    external
    view
    returns (Duel memory);
}
