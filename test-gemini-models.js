// Test different Gemini model names
const API_KEY = 'AIzaSyC5WHdBHET15wuB8SCKm_E7oh9zomodjUE';

const models = [
  'gemini-2.5-flash-lite-preview',
  'gemini-2.5-flash-lite-preview-06-17',
  'gemini-2.5-flash-lite',
  'gemini-1.5-flash-8b-latest',
  'gemini-1.5-flash-8b'
];

async function testModel(modelName) {
  console.log(`\nTesting model: ${modelName}`);
  console.log('='.repeat(50));
  
  const url = `https://generativelanguage.googleapis.com/v1/models/${modelName}:generateContent?key=${API_KEY}`;
  
  const body = {
    contents: [{
      role: 'user',
      parts: [{ text: 'Hi' }]
    }],
    generationConfig: {
      temperature: 1.0,
      maxOutputTokens: 50,
      candidateCount: 1
    }
  };

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });

    console.log(`Status: ${response.status}`);
    
    if (response.ok) {
      const result = await response.json();
      console.log('✅ Model works!');
      console.log('Response:', result.candidates?.[0]?.content?.parts?.[0]?.text);
    } else {
      const error = await response.text();
      console.log('❌ Model failed');
      console.log('Error:', error);
    }
  } catch (error) {
    console.error('Network error:', error);
  }
}

// Test all models
async function testAllModels() {
  for (const model of models) {
    await testModel(model);
  }
}

testAllModels();