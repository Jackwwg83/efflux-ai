// List all available Gemini models
const API_KEY = 'AIzaSyC5WHdBHET15wuB8SCKm_E7oh9zomodjUE';

async function listModels() {
  const url = `https://generativelanguage.googleapis.com/v1/models?key=${API_KEY}`;
  
  try {
    const response = await fetch(url);
    const data = await response.json();
    
    console.log('Available Gemini Models:');
    console.log('='.repeat(80));
    
    if (data.models) {
      // Filter for models that support generateContent
      const generateContentModels = data.models.filter(model => 
        model.supportedGenerationMethods?.includes('generateContent')
      );
      
      generateContentModels.forEach(model => {
        console.log(`\nModel: ${model.name}`);
        console.log(`Display Name: ${model.displayName}`);
        console.log(`Description: ${model.description}`);
        console.log(`Version: ${model.version || 'N/A'}`);
        console.log(`Input Token Limit: ${model.inputTokenLimit}`);
        console.log(`Output Token Limit: ${model.outputTokenLimit}`);
        console.log(`Supported Methods: ${model.supportedGenerationMethods.join(', ')}`);
      });
      
      console.log('\n' + '='.repeat(80));
      console.log('Models that support generateContent:');
      generateContentModels.forEach(model => {
        console.log(`- ${model.name.replace('models/', '')}`);
      });
    }
  } catch (error) {
    console.error('Error listing models:', error);
  }
}

listModels();