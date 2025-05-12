\
# Code Structure Analysis for Elixir Distributed Game

This document provides an overview of the key modules in the Elixir distributed game project, focusing on their roles in player management, network communication, and game logic.

## Core Modules

### 1. `GameProject.UI`
-   **Responsibility**: User Interface and Interaction.
-   **Functionality**:
    -   Presents the main menus (initial and in-game).
    -   Handles user input for actions like changing alias, creating a network, joining a network, selecting a team, rolling dice, etc.
    -   Initiates HTTP requests to other nodes (e.g., when joining a network) using `HTTPoison`.
    -   Interacts with local GenServers like `GameServer` and `PlayerRegistry` to update or fetch state.
    -   Starts the `HTTPServer` and other necessary processes for the local node.

### 2. `GameProject.HTTPServer`
-   **Responsibility**: Handles incoming HTTP requests from other nodes.
-   **Functionality**:
    -   Uses `Plug.Router` to define endpoints like:
        -   `/join`: For new players requesting to join the network.
        -   `/message`: For receiving distributed messages (e.g., player updates, game events).
        -   `/join_team`: For requests to join a specific team.
        -   `/approve_join`: For team members to vote on a join request.
        -   `/roll_dice`: For a player to take their turn.
        -   `/game_state`: To provide the current game state.
    -   Parses incoming JSON payloads.
    -   Interacts with `PlayerRegistry` to update player lists (e.g., adding a new player).
    -   Interacts with `GameServer` to modify or query game state (e.g., updating scores).
    -   Calls `MessageDistribution` to propagate information to other nodes.
    -   Uses `MessageHandler` to process the content of generic `/message` payloads.

### 3. `GameProject.PlayerRegistry`
-   **Responsibility**: Manages the state of known players in the network.
-   **Functionality**:
    -   Implemented as a `GenServer`.
    -   Maintains a map of players, keyed by their alias. Each player is a `GameProject.Models.Player` struct.
    -   Provides an API to:
        -   Add a new player.
        -   Remove a player.
        -   Update a player's information (e.g., team, alias).
        -   Get a specific player by alias or address.
        -   Get all players, or players grouped by team, or players without a team.
    -   Ensures that player data is consistent locally.

### 4. `GameProject.GameServer`
-   **Responsibility**: Manages the overall game state.
-   **Functionality**:
    -   Implemented as a `GenServer`.
    -   Holds the `GameProject.Models.GameState` struct, which includes:
        -   Instance ID, turn number, scores per team, players' turn history, max score, game status (:awaiting_players, :in_progress, :finished).
    -   Provides an API to:
        -   Create a new game (when a player starts a network).
        -   Set an initial game state (when joining an existing network).
        -   Get the current game state.
        -   Update team scores.
        -   Register a player's turn.
        -   Select the next player for a turn.
        -   Advance to the next turn.
        -   End the game.

### 5. `GameProject.MessageDistribution`
-   **Responsibility**: Implements the "distribute" message protocol.
-   **Functionality**:
    -   Takes a message payload and a list of target players.
    -   Groups players by team (including a group for players without a team).
    -   Selects a random representative from each group.
    -   Each representative is tasked with sending the message to all members of their own group (including themselves).
    -   Uses `HTTPoison` to send messages to other nodes via their `/message` endpoint.
    -   Handles failures in sending messages: if a player is unreachable after retries, they are removed from the local `PlayerRegistry`, and a new "distribute" message is sent to inform other players to also remove the disconnected player.
    -   Includes a placeholder for gRPC logging.

### 6. `GameProject.MessageHandler`
-   **Responsibility**: Processes the content of messages received at the `/message` HTTP endpoint.
-   **Functionality**:
    -   Acts upon different message types, such as:
        -   `:new_player_joined`: Adds the new player to the local `PlayerRegistry`.
        -   `:player_disconnected`: Removes the specified player from the local `PlayerRegistry`.
        -   `:player_joined_team`: Updates a player's team in the local `PlayerRegistry`.
        -   `:score_update`: Updates the game score in the local `GameServer`.
    -   Ensures the local node's state is updated based on information received from other nodes.

### 7. `GameProject.Network`
-   **Responsibility**: Provides network utility functions.
-   **Functionality**:
    -   Gets the local IP address of the node.
    -   Gets the public IP address of the node (using an external service).

### 8. Model Structs (`GameProject.Models.Player`, `GameProject.Models.GameState`)
-   **Responsibility**: Define the data structures for players and game state.
-   **Functionality**:
    -   `Player`: Holds address, alias, team, and secret number. Includes functions to create new players and convert from/to maps.
    -   `GameState`: Holds all game-related information. Includes functions to initialize and update the state.

## Interaction Flow (Example: New Player Joins)

1.  **P3 (New Player via UI)**: Decides to join an existing network, provides P2's address.
2.  **P3's UI**: Sends a POST request to `http://P2_address/join` with P3's info.
3.  **P2's HTTPServer (`/join` endpoint)**:
    a.  Authenticates P3.
    b.  Creates a `Player` struct for P3.
    c.  Adds P3 to its local `PlayerRegistry`.
    d.  Calls `MessageDistribution.distribute_message(%{type: :new_player_joined, player_data: P3}, P2.all_known_players)`.
    e.  Responds to P3 with the current list of players (from P2's `PlayerRegistry`) and game configuration.
4.  **P3's UI**: Receives the response, updates its local `PlayerRegistry` and `GameServer` with the data from P2.
5.  **P2's MessageDistribution**:
    a.  Selects representatives (e.g., P2 itself, and P1 if P1 is in a different "group").
    b.  The representative(s) send the `:new_player_joined` message (about P3) to all players in their respective groups. This involves HTTP POSTs to each player's `/message` endpoint (with retries).
6.  **P1's HTTPServer (`/message` endpoint)**:
    a.  Receives the message about P3.
    b.  Calls `MessageHandler.handle_message`.
7.  **P1's MessageHandler**:
    a.  Processes the `:new_player_joined` message.
    b.  Adds P3 to P1's local `PlayerRegistry`.

This flow, with the added robustness in `MessageDistribution`, aims to ensure all players maintain a consistent view of the network.
