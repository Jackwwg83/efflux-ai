// Test Google Gemini API directly
const API_KEY = 'AIzaSyC5WHdBHET15wuB8SCKm_E7oh9zomodjUE';
const MODEL = 'gemini-2.5-flash'; // 使用正确的模型名称

async function testGoogleAPI() {
  const url = `https://generativelanguage.googleapis.com/v1/models/${MODEL}:generateContent?key=${API_KEY}`;
  
  const body = {
    contents: [{
      role: 'user',
      parts: [{ text: 'Hello, can you respond to this test message?' }]
    }],
    generationConfig: {
      temperature: 1.0,
      maxOutputTokens: 100,
      candidateCount: 1
    }
  };

  try {
    console.log('Testing Google API with URL:', url);
    console.log('Request body:', JSON.stringify(body, null, 2));
    
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });

    console.log('Response status:', response.status);
    console.log('Response headers:', response.headers);
    
    const result = await response.json();
    console.log('Response body:', JSON.stringify(result, null, 2));
    
    if (!response.ok) {
      console.error('API Error:', result);
    } else {
      console.log('Success! Generated text:', result.candidates?.[0]?.content?.parts?.[0]?.text);
    }
  } catch (error) {
    console.error('Error calling Google API:', error);
  }
}

// Run the test
testGoogleAPI();