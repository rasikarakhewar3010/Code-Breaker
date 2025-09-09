% backend/codebreaker.pl

% Load SWI-Prolog's JSON library for easy output
:- use_module(library(http/json)).
:- use_module(library(random)). % For random number generation

% --- Helper Predicates ---

% Predicate for starting a new game (generating a secret code)
% Generates a list of 4 random digits (0-9).
generate_secret_code(CodeList) :-
    length(CodeList, 4), % A 4-digit code (list of 4 elements)
    maplist(random_digit, CodeList). % Each element is a random digit 0-9

random_digit(D) :-
    random_between(0, 9, D).

% --- Core Game Logic: compare_guess/4 (Mastermind Style) ---
% Secret: List of 4 digits (e.g., [1,2,3,4])
% Guess: List of 4 digits (e.g., [1,5,3,6])
% CorrectPlace: Number of digits correct in value AND position (black pegs)
% WrongPlace: Number of digits correct in value but WRONG position (white pegs)

compare_guess(Secret, Guess, CorrectPlace, WrongPlace) :-
    % Step 1: Identify correct position matches
    match_correct_position(Secret, Guess, TempSecret, TempGuess, CorrectPlace),

    % Step 2: Identify correct value, wrong position matches from remaining digits
    count_wrong_position(TempSecret, TempGuess, 0, WrongPlace).

% match_correct_position(+Secret, +Guess, -ModifiedSecret, -ModifiedGuess, -Count)
% Recursively counts digits that are correct in both value and position.
% It modifies the lists by marking matched digits with 'used' to prevent double-counting.
match_correct_position([], [], [], [], 0).
match_correct_position([S|Ss], [G|Gs], [MS|MSs], [MG|MGs], Count) :-
    match_correct_position(Ss, Gs, MSs, MGs_tail, TailCount),
    (   S == G % If a digit matches at the same position
    ->  MS = used, MG = used, Count is TailCount + 1, MGs = MGs_tail % Mark as 'used' and increment count
    ;   MS = S, MG = G, Count = TailCount, MGs = MGs_tail % If no match, keep original digit
    ).

% count_wrong_position(+RemainingSecret, +RemainingGuess, +Acc, -WrongPlace)
% Counts digits that are correct in value but in the wrong position from the remaining digits.
% Uses 'select' to remove a matched digit from the secret list for each guess digit,
% ensuring that each secret digit is only matched once.
count_wrong_position(SecretList, GuessList, AccIn, AccOut) :-
    (   GuessList = [] % Base case: no more guess digits to check
    ->  AccOut = AccIn
    ;   GuessList = [G|Gs], % Take the first digit from the remaining guess list
        (   select(G, SecretList, NewSecretList) % Check if this guess digit 'G' exists in the remaining SecretList
        ->  AccNext is AccIn + 1, % If found, it's a wrong-place match
            count_wrong_position(NewSecretList, Gs, AccNext, AccOut) % Recursively check with the matched secret digit removed
        ;   % If 'G' is not found in SecretList, no match for this digit
            count_wrong_position(SecretList, Gs, AccIn, AccOut) % Recursively check with same SecretList
        )
    ).

% --- Node.js API Interface: main_codebreaker_query/4 ---
% This is the main entry point for Node.js to interact with Prolog.
% Action: 'start_game' or 'guess(GuessString)'
% CurrentSecretCodeAtom: String representation of the secret code list (e.g., "[1,2,3,4]")
% GuessAtom: String representation of the guess (e.g., "1234") - Only used for 'guess' action
% ResponseJson: The JSON object to be printed to stdout.

main_codebreaker_query(ActionTerm, CurrentSecretCodeAtom, GuessAtom, _ResponseJson) :-
    (   ActionTerm = start_game % Action to start a new game
    ->  generate_secret_code(SecretCodeList), % Generate a new random code
        maplist(atom_string, SecretCodeAtoms, SecretCodeList), % Convert digits to atoms, then atoms to strings
        atomic_list_concat(SecretCodeAtoms, '', SecretCodeString), % Concatenate to "1234"
        json_write(current_output, json{success: true, action: 'start_game', secret_code_str: SecretCodeString, secret_code_list: SecretCodeList, message: 'New game started. Guess the 4-digit code!'})

    ;   ActionTerm = guess(GuessStr) % Action to make a guess
    ->  % Convert current secret code string from Node.js (e.g., "[1,2,3,4]") to Prolog list
        term_string(SecretCodeList, CurrentSecretCodeAtom),
        % Convert guess string from Node.js (e.g., "1234") to Prolog list of digits
        atom_chars(GuessStr, GuessCharList), % '1234' -> ['1','2','3','4']
        maplist(atom_number, GuessCharList, GuessList), % ['1','2','3','4'] -> [1,2,3,4]

        % Compare the guess to the secret code
        compare_guess(SecretCodeList, GuessList, CorrectPlace, WrongPlace),

        % Determine game win status and message
        (   CorrectPlace = 4 % If all 4 are correct and in place
        ->  Message = 'Congratulations! You cracked the code!',
            GameWon = true
        ;   format(atom(Message), 'Correct: ~w, Wrong Place: ~w', [CorrectPlace, WrongPlace]),
            GameWon = false
        ),
        json_write(current_output, json{success: true, action: 'guess', correct_place: CorrectPlace, wrong_place: WrongPlace, message: Message, game_won: GameWon})
    ;   % Default/Error case for unrecognized actions
        json_write(current_output, json{success: false, message: 'Invalid action.'})
    ).