// backend/server.js
const express = require('express');
const { exec } = require('child_process');
const cors = require('cors');
const path = require('path');

const app = express();
const port = 3000;

app.use(express.json());
app.use(cors());

// --- Game State ---
let codebreakerGameState = {
    secretCodeList: [],
    secretCodeString: '',
    guesses: [],
    gameWon: false,
    message: 'Welcome to Code Breaker! Click "New Game" to start.',
};

// Path to the Prolog file
const prologFilePath = path.join(__dirname, 'codebreaker.pl');

// ⚡ Absolute path to SWI-Prolog executable (update if your installation path differs)
const prologExecutable = `"C:\\Program Files\\swipl\\bin\\swipl.exe"`;

// Helper to execute Prolog query
const executeProlog = (actionTerm, currentSecretCodeListAtom, guessAtom = '[]') => {
    const goal = `main_codebreaker_query(${actionTerm}, '${currentSecretCodeListAtom}', '${guessAtom}', _ResponseJson)`;
    const command = `${prologExecutable} -q -s ${prologFilePath} -g "${goal}" -t halt.`;

    console.log(`Executing Prolog command: ${command}`);

    return new Promise((resolve, reject) => {
        exec(command, (error, stdout, stderr) => {
            if (error) {
                console.error(`exec error: ${error}`);
                return reject({ message: 'Prolog engine error', error: stderr.trim() });
            }
            if (stderr) {
                console.warn(`Prolog stderr: ${stderr.trim()}`);
            }
            try {
                const prologResult = JSON.parse(stdout.trim());
                resolve(prologResult);
            } catch (parseError) {
                console.error('Failed to parse Prolog output:', stdout, parseError);
                reject({ message: 'Failed to parse Prolog output', raw: stdout.trim() });
            }
        });
    });
};

// --- API Endpoints ---
app.post('/api/new_game', async (req, res) => {
    try {
        const prologResult = await executeProlog('start_game', '[]');
        if (prologResult.success) {
            codebreakerGameState = {
                secretCodeList: prologResult.secret_code_list,
                secretCodeString: prologResult.secret_code_str,
                guesses: [],
                gameWon: false,
                message: prologResult.message,
            };
            res.json({ success: true, gameState: codebreakerGameState });
        } else {
            res.status(500).json({ success: false, message: prologResult.message });
        }
    } catch (error) {
        console.error('Error starting new game:', error);
        res.status(500).json({ success: false, message: error.message, error: error.error || error.raw });
    }
});

app.post('/api/guess', async (req, res) => {
    const { guess } = req.body;
    if (!guess || !/^\d{4}$/.test(guess)) {
        return res.status(400).json({ success: false, message: 'Invalid guess. Please enter a 4-digit number.' });
    }
    if (codebreakerGameState.gameWon) {
        return res.status(400).json({ success: false, message: 'Game already won! Start a new game.' });
    }
    if (!codebreakerGameState.secretCodeList.length) {
        return res.status(400).json({ success: false, message: 'No game in progress. Start a new game first.' });
    }

    try {
        const secretCodeListAtom = JSON.stringify(codebreakerGameState.secretCodeList);
        const prologResult = await executeProlog(`guess('${guess}')`, secretCodeListAtom, guess);

        if (prologResult.success) {
            const newGuessEntry = {
                guess,
                hints: {
                    correctPlace: prologResult.correct_place,
                    wrongPlace: prologResult.wrong_place,
                },
                message: prologResult.message,
            };

            codebreakerGameState.guesses.push(newGuessEntry);
            codebreakerGameState.gameWon = prologResult.game_won;
            codebreakerGameState.message = prologResult.message;

            res.json({ success: true, gameState: codebreakerGameState });
        } else {
            res.status(500).json({ success: false, message: prologResult.message });
        }
    } catch (error) {
        console.error('Error submitting guess:', error);
        res.status(500).json({ success: false, message: error.message, error: error.error || error.raw });
    }
});

app.get('/*', (req, res) => {
    res.status(404).send('Cannot GET ' + req.originalUrl + ' - This is an API server.');
});

app.listen(port, () => {
    console.log(`Code Breaker backend server listening at http://localhost:${port}`);
});
